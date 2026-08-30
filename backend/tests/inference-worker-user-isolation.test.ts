/**
 * M-1b step 3 (#135) — proves the inference worker's per-user scoping directly, the way the other
 * worker tests in this directory already drive `runWorker`/`narrateNextPattern` against a real
 * (throwaway) diary file with Ollama stubbed out.
 *
 * `tests/e2e/user-isolation.test.ts` (#46) is explicitly the model for this file but deliberately
 * does not cover the worker itself — it is a separate process with its own job-selection path and
 * no HTTP route to exercise (see that file's top-of-file note). This is the worker's own
 * isolation suite: two users, jobs queued for each, and — for every assertion — both directions
 * checked, not just absence: what user A's job wrote lands exactly under user A, and running user
 * B's job afterwards neither reuses nor disturbs any of it, and vice versa.
 *
 * Two write paths are covered, matching the two places `worker.ts` writes at all (per the PR's
 * enumeration):
 *  - `processJob`/`applyAnalysis` — the entry-analysis path: `diary_entries`, `entry_feelings`,
 *    `topics`, `entry_topics`, `entry_topic_feelings`, `inference_jobs`.
 *  - `narrateNextPattern` — the background narration path: `patterns`.
 *
 * The topic-scoping assertion below is the one most likely to catch a real regression: both users
 * write an entry mentioning "coffee". If `applyAnalysis`'s `findTopic`/`insertTopic` ever forgot
 * their `user_id` filter, user B's job would find and silently reuse user A's existing "coffee"
 * topic row instead of creating its own — exactly the class of cross-user leak this ticket exists
 * to close, and exactly what `topics.UNIQUE (user_id, name)` (`schema.ts`) is there to make
 * possible to have two of.
 */

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { encodeDate, encodeDateTime, encodeJson, nowUtc, todayLocal } from '../src/db/codecs';
import { openDiary, type DiaryDatabase } from '../src/db/database';
import { initDiary } from '../src/db/init';
import { narrateNextPattern, runWorker } from '../src/inference/worker';
import { templateSuggestionFor } from '../src/insights/patterns.service';

const USER_A = '11111111-1111-1111-1111-111111111111';
const USER_B = '22222222-2222-2222-2222-222222222222';

let dir: string;
let dbPath: string;
let fetchSpy: ReturnType<typeof vi.spyOn> | undefined;

/** `assertCompatible` (FR-018) refuses to start against a diary whose `user_id` columns name a
 *  user that does not exist in `users` — real rows for both accounts are required for `runWorker`
 *  to open the diary at all, independent of `foreign_keys` being off at the SQLite layer. */
function seedUsers(db: DiaryDatabase): void {
  const now = encodeDateTime(nowUtc());
  const insertUser = db.prepare(
    'INSERT INTO users (id, email, password_hash, created_at) VALUES (?, ?, ?, ?)',
  );
  insertUser.run(USER_A, 'reader-a@example.com', 'disabled:no-password-set', now);
  insertUser.run(USER_B, 'reader-b@example.com', 'disabled:no-password-set', now);
}

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-worker-isolation-'));
  dbPath = path.join(dir, 'diary.db');
  initDiary(dbPath);
  const db = openDiary(dbPath);
  seedUsers(db);
  db.close();
  process.env.DATABASE_PATH = dbPath;
});

afterEach(() => {
  delete process.env.DATABASE_PATH;
  fetchSpy?.mockRestore();
  fetchSpy = undefined;
  fs.rmSync(dir, { recursive: true, force: true });
});

/** Stands in for Ollama's `/api/chat` for an entry-analysis call, the same convention
 *  `inference-pairings.test.ts` uses: the real request always carries a non-empty `messages`
 *  array, the `keep_alive: 0` unload ping never does. */
function mockAnalysis(content: unknown): void {
  fetchSpy?.mockRestore();
  fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation(async (_url, init) => {
    const body = init?.body ? (JSON.parse(String(init.body)) as { messages?: unknown[] }) : {};
    const isRealCall = Array.isArray(body.messages) && body.messages.length > 0;
    return {
      ok: true,
      status: 200,
      json: async () =>
        isRealCall ? { message: { content: JSON.stringify(content) } } : { message: {} },
    } as Response;
  });
}

/** Same stand-in, for a narration (`ollamaSuggestion`) call. */
function mockSuggestion(suggestion: string): void {
  fetchSpy?.mockRestore();
  fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation(async (_url, init) => {
    const body = init?.body ? (JSON.parse(String(init.body)) as { messages?: unknown[] }) : {};
    const isRealCall = Array.isArray(body.messages) && body.messages.length > 0;
    return {
      ok: true,
      status: 200,
      json: async () =>
        isRealCall ? { message: { content: JSON.stringify({ suggestion }) } } : { message: {} },
    } as Response;
  });
}

function insertQueuedEntry(
  db: DiaryDatabase,
  entryId: string,
  userId: string,
  rawText: string,
): void {
  const now = encodeDateTime(nowUtc());
  db.prepare(
    `INSERT INTO diary_entries
     (id, user_id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source, version)
     VALUES (?, ?, ?, ?, ?, 'freeform', ?, NULL, 'unset', 1)`,
  ).run(entryId, userId, now, now, encodeDate(todayLocal()), rawText);
  db.prepare(
    `INSERT INTO inference_jobs
     (id, user_id, kind, entry_id, status, result_json, error_text, attempts, created_at, started_at, completed_at)
     VALUES (?, ?, 'entry_analysis', ?, 'queued', NULL, NULL, 0, ?, NULL, NULL)`,
  ).run(`${entryId}-job`, userId, entryId, now);
}

interface EntryRow {
  feeling_key: string | null;
  feeling_source: string;
}

function readEntry(db: DiaryDatabase, entryId: string): EntryRow {
  return db
    .prepare('SELECT feeling_key, feeling_source FROM diary_entries WHERE id = ?')
    .get(entryId) as EntryRow;
}

interface TopicRow {
  id: string;
  user_id: string;
  name: string;
}

function readTopics(db: DiaryDatabase, name: string): TopicRow[] {
  return db
    .prepare('SELECT id, user_id, name FROM topics WHERE name = ? ORDER BY user_id')
    .all(name) as TopicRow[];
}

interface EntryTopicRow {
  entry_id: string;
  topic_id: string;
  user_id: string;
}

function readEntryTopics(db: DiaryDatabase, entryId: string): EntryTopicRow[] {
  return db
    .prepare('SELECT entry_id, topic_id, user_id FROM entry_topics WHERE entry_id = ?')
    .all(entryId) as EntryTopicRow[];
}

interface PairingRow {
  entry_id: string;
  topic_id: string;
  user_id: string;
  feeling_key: string;
  source: string;
}

function readPairings(db: DiaryDatabase, entryId: string): PairingRow[] {
  return db
    .prepare(
      `SELECT entry_id, topic_id, user_id, feeling_key, source
       FROM entry_topic_feelings WHERE entry_id = ?`,
    )
    .all(entryId) as PairingRow[];
}

interface PatternStateRow {
  suggestion_text: string;
  narration_attempts: number;
  narration_next_attempt_at: string | null;
}

describe('inference worker — per-user scoping (#135)', () => {
  it('an entry_analysis job for user A never writes user B rows, and a later job for user B never writes user A rows', async () => {
    const db = openDiary(dbPath);

    insertQueuedEntry(db, 'entry-a', USER_A, 'A quiet coffee at the desk.');
    mockAnalysis({
      feelings: [{ group_key: 'steady', feeling_key: 'content', confidence: 0.7 }],
      topics: ['coffee'],
      topic_feelings: [{ topic: 'coffee', feeling_keys: ['content'] }],
    });
    await runWorker(true);

    // Direction 1: user A's job wrote exactly what it should, under user A.
    const afterA = readEntry(db, 'entry-a');
    expect(afterA).toEqual({ feeling_key: 'content', feeling_source: 'suggested' });
    const topicsAfterA = readTopics(db, 'coffee');
    expect(topicsAfterA).toHaveLength(1);
    expect(topicsAfterA[0].user_id).toBe(USER_A);
    const topicIdA = topicsAfterA[0].id;
    expect(readEntryTopics(db, 'entry-a')).toEqual([
      { entry_id: 'entry-a', topic_id: topicIdA, user_id: USER_A },
    ]);
    expect(readPairings(db, 'entry-a')).toEqual([
      {
        entry_id: 'entry-a',
        topic_id: topicIdA,
        user_id: USER_A,
        feeling_key: 'content',
        source: 'suggested',
      },
    ]);

    // Now queue and run an entry for user B, proposing the exact same topic phrase and a
    // different feeling — the scenario that would expose a `findTopic`/`insertTopic` that forgot
    // its `user_id` filter.
    insertQueuedEntry(db, 'entry-b', USER_B, 'Coffee before the shift, feeling anxious.');
    mockAnalysis({
      feelings: [{ group_key: 'low', feeling_key: 'anxious', confidence: 0.8 }],
      topics: ['coffee'],
      topic_feelings: [{ topic: 'coffee', feeling_keys: ['anxious'] }],
    });
    await runWorker(true);

    // Direction 2: running user B's job left every one of user A's rows exactly as they were —
    // not merely "still present," byte-identical to what direction 1 already confirmed.
    expect(readEntry(db, 'entry-a')).toEqual(afterA);
    expect(readEntryTopics(db, 'entry-a')).toEqual([
      { entry_id: 'entry-a', topic_id: topicIdA, user_id: USER_A },
    ]);
    expect(readPairings(db, 'entry-a')).toEqual([
      {
        entry_id: 'entry-a',
        topic_id: topicIdA,
        user_id: USER_A,
        feeling_key: 'content',
        source: 'suggested',
      },
    ]);

    // And user B's own job wrote exactly what it should, under user B — including a *second*,
    // distinct "coffee" topic row rather than reusing user A's.
    const topicsAfterB = readTopics(db, 'coffee');
    expect(topicsAfterB).toHaveLength(2);
    const topicA = topicsAfterB.find((t) => t.user_id === USER_A);
    const topicB = topicsAfterB.find((t) => t.user_id === USER_B);
    expect(topicA?.id).toBe(topicIdA);
    expect(topicB).toBeDefined();
    expect(topicB!.id).not.toBe(topicIdA);

    expect(readEntry(db, 'entry-b')).toEqual({
      feeling_key: 'anxious',
      feeling_source: 'suggested',
    });
    expect(readEntryTopics(db, 'entry-b')).toEqual([
      { entry_id: 'entry-b', topic_id: topicB!.id, user_id: USER_B },
    ]);
    expect(readPairings(db, 'entry-b')).toEqual([
      {
        entry_id: 'entry-b',
        topic_id: topicB!.id,
        user_id: USER_B,
        feeling_key: 'anxious',
        source: 'suggested',
      },
    ]);

    db.close();
  });

  it('narrateNextPattern only ever writes the pattern it picked, never the other user’s pattern row', async () => {
    const db = openDiary(dbPath);
    const now = encodeDateTime(nowUtc());
    const suggestion = 'Try a short walk after lunch and see whether the afternoon feels lighter.';

    function seedPattern(id: string, userId: string, topicId: string, topicName: string): void {
      db.prepare(
        `INSERT INTO topics (id, user_id, name, aliases, first_seen_at, last_seen_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      ).run(topicId, userId, topicName, encodeJson([]), now, now);
      db.prepare(
        `INSERT INTO patterns
         (id, user_id, topic_id, feeling_key, occurrence_count, narrative_text, suggestion_text,
          direction, first_detected_at, last_updated_at, narration_attempts, narration_next_attempt_at)
         VALUES (?, ?, ?, 'energised', 5, 'You felt energised in 5 recent entries mentioning walking.',
                 ?, 'keep', ?, ?, 0, NULL)`,
      ).run(id, userId, topicId, templateSuggestionFor('energised', topicName), now, now);
    }

    // Same topic name, same feeling, same template text, for two different users — the shape most
    // likely to expose a query that picked or updated a pattern without checking its owner.
    seedPattern('pattern-a', USER_A, 'topic-a', 'walking');
    seedPattern('pattern-b', USER_B, 'topic-b', 'walking');

    function readPattern(id: string): PatternStateRow {
      return db
        .prepare(
          `SELECT suggestion_text, narration_attempts, narration_next_attempt_at
           FROM patterns WHERE id = ?`,
        )
        .get(id) as PatternStateRow;
    }

    const beforeB = readPattern('pattern-b');

    // Both patterns tie on `last_updated_at`, so the candidate scan's `ORDER BY ... p.id` picks
    // `pattern-a` first, deterministically.
    mockSuggestion(suggestion);
    expect(await narrateNextPattern(db)).toBe('wrote');

    const afterA = readPattern('pattern-a');
    expect(afterA).toEqual({
      suggestion_text: suggestion,
      narration_attempts: 0,
      narration_next_attempt_at: null,
    });
    // Direction 1: narrating user A's pattern left user B's completely untouched — same template,
    // same attempt/backoff state as before the call.
    expect(readPattern('pattern-b')).toEqual(beforeB);

    // `pattern-a` no longer matches its template, so this second call can only pick `pattern-b`.
    mockSuggestion(suggestion);
    expect(await narrateNextPattern(db)).toBe('wrote');

    // Direction 2: narrating user B's pattern did not revert or otherwise touch user A's
    // already-written suggestion.
    expect(readPattern('pattern-a')).toEqual(afterA);
    expect(readPattern('pattern-b')).toEqual({
      suggestion_text: suggestion,
      narration_attempts: 0,
      narration_next_attempt_at: null,
    });

    db.close();
  });
});
