/**
 * E-1a acceptance criterion: "Worker produces pair suggestions for a mixed-valence test entry
 * (integration test with a stubbed/mocked model response — do not depend on live Ollama in CI)."
 *
 * This runs the real worker pipeline (`runWorker`, `processJob`, `applyAnalysis`) end to end
 * against a real (throwaway) diary file, with `global.fetch` stubbed to stand in for Ollama. It is
 * deliberately not `llm-analysis.eval.test.ts`, which needs a live model and is skipped by
 * default — this file must run in ordinary CI.
 */

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { encodeDate, encodeDateTime, nowUtc, todayLocal } from '../src/db/codecs';
import { openDiary, type DiaryDatabase } from '../src/db/database';
import { initDiary } from '../src/db/init';
import { runWorker } from '../src/inference/worker';

let dir: string;
let dbPath: string;
let fetchSpy: ReturnType<typeof vi.spyOn> | undefined;

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-pairing-'));
  dbPath = path.join(dir, 'diary.db');
  initDiary(dbPath);
  // `runWorker` opens its own connection via `loadConfig().databasePath`, the same wiring
  // `llm-analysis.eval.test.ts` uses to point the worker at a throwaway diary.
  process.env.DATABASE_PATH = dbPath;
});

afterEach(() => {
  delete process.env.DATABASE_PATH;
  fetchSpy?.mockRestore();
  fetchSpy = undefined;
  fs.rmSync(dir, { recursive: true, force: true });
});

/**
 * Stands in for Ollama's `/api/chat`. `worker.ts` makes two calls per analysis: the real request
 * (a non-empty `messages` array, `format` set to the structured-output schema) and a
 * fire-and-forget empty-message ping in its `finally` block to release the model. Only the first
 * needs a real body.
 */
function mockOllama(content: unknown): void {
  fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation(async (_url, init) => {
    const body = init?.body ? (JSON.parse(String(init.body)) as { messages?: unknown[] }) : {};
    const isAnalysisCall = Array.isArray(body.messages) && body.messages.length > 0;
    return {
      ok: true,
      status: 200,
      json: async () =>
        isAnalysisCall ? { message: { content: JSON.stringify(content) } } : { message: {} },
    } as Response;
  });
}

function insertQueuedEntry(db: DiaryDatabase, entryId: string, rawText: string): void {
  const now = encodeDateTime(nowUtc());
  db.prepare(
    `INSERT INTO diary_entries
     (id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source, version)
     VALUES (?, ?, ?, ?, 'freeform', ?, NULL, 'unset', 1)`,
  ).run(entryId, now, now, encodeDate(todayLocal()), rawText);
  db.prepare(
    `INSERT INTO inference_jobs
     (id, kind, entry_id, status, result_json, error_text, attempts, created_at, started_at, completed_at)
     VALUES (?, 'entry_analysis', ?, 'queued', NULL, NULL, 0, ?, NULL, NULL)`,
  ).run(`${entryId}-job`, entryId, now);
}

function readPairings(
  entryId: string,
): Array<{ topic: string; feeling_key: string; source: string }> {
  const db = openDiary(dbPath);
  try {
    return db
      .prepare(
        `SELECT t.name AS topic, etf.feeling_key, etf.source
         FROM entry_topic_feelings etf JOIN topics t ON t.id = etf.topic_id
         WHERE etf.entry_id = ? ORDER BY t.name, etf.feeling_key`,
      )
      .all(entryId) as Array<{ topic: string; feeling_key: string; source: string }>;
  } finally {
    db.close();
  }
}

describe('worker pairing extraction (E-1a)', () => {
  it('stores a suggested pairing for each topic↔feeling the model ties together', async () => {
    const seed = openDiary(dbPath);
    insertQueuedEntry(
      seed,
      'mixed-1',
      'Missed my workout again, which was disappointing. But a call with family felt warm.',
    );
    seed.close();

    mockOllama({
      feelings: [
        { group_key: 'low', feeling_key: 'disappointed', confidence: 0.9 },
        { group_key: 'uplifted', feeling_key: 'grateful', confidence: 0.8 },
      ],
      topics: ['exercise', 'family'],
      topic_feelings: [
        { topic: 'exercise', feeling_keys: ['disappointed'] },
        { topic: 'family', feeling_keys: ['grateful'] },
      ],
    });

    await runWorker(true);

    const db = openDiary(dbPath);
    const job = db
      .prepare('SELECT status FROM inference_jobs WHERE entry_id = ?')
      .get('mixed-1') as { status: string };
    db.close();
    expect(job.status).toBe('completed');

    expect(readPairings('mixed-1')).toEqual([
      { topic: 'exercise', feeling_key: 'disappointed', source: 'suggested' },
      { topic: 'family', feeling_key: 'grateful', source: 'suggested' },
    ]);
  });

  it('leaves a topic with no clear feeling association unpaired — an empty list is a normal answer', async () => {
    const seed = openDiary(dbPath);
    insertQueuedEntry(seed, 'ambiguous-1', 'Worked from the office today, then read for a while.');
    seed.close();

    mockOllama({
      feelings: [{ group_key: 'steady', feeling_key: 'content', confidence: 0.6 }],
      topics: ['work', 'reading'],
      topic_feelings: [
        { topic: 'work', feeling_keys: [] },
        { topic: 'reading', feeling_keys: [] },
      ],
    });

    await runWorker(true);

    expect(readPairings('ambiguous-1')).toEqual([]);
  });

  it('never stores a pairing for a feeling the model did not also propose for the entry', async () => {
    const seed = openDiary(dbPath);
    insertQueuedEntry(seed, 'untrustworthy-1', 'A long walk in the park.');
    seed.close();

    // The model proposes only `content` as a feeling, but tries to pair `walking` with `lonely` —
    // a feeling it never actually reported. `reconcilePairings` must not take the model's word for
    // it: aspect-based extraction is "which of the feelings already found", never a second guess.
    mockOllama({
      feelings: [{ group_key: 'steady', feeling_key: 'content', confidence: 0.7 }],
      topics: ['walking'],
      topic_feelings: [{ topic: 'walking', feeling_keys: ['lonely'] }],
    });

    await runWorker(true);

    expect(readPairings('untrustworthy-1')).toEqual([]);
  });

  it('never stores a pairing for a topic that was not actually extracted', async () => {
    const seed = openDiary(dbPath);
    insertQueuedEntry(seed, 'phantom-topic-1', 'A quiet, ordinary evening.');
    seed.close();

    // `travel` never appears in `topics`, so nothing about it may be stored, however confidently
    // the model pairs it.
    mockOllama({
      feelings: [{ group_key: 'steady', feeling_key: 'calm', confidence: 0.5 }],
      topics: [],
      topic_feelings: [{ topic: 'travel', feeling_keys: ['calm'] }],
    });

    await runWorker(true);

    expect(readPairings('phantom-topic-1')).toEqual([]);
  });
});
