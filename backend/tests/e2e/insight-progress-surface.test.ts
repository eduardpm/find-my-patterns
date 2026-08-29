/**
 * #37 (L-2): the insight progress surface — near-threshold counts served alongside the pattern
 * echo (`GET /entries/:entryId/echo`'s `progress` field, `src/insights/progress.service.ts`).
 *
 * Three things this suite has to nail down, all from the issue's acceptance criteria:
 *
 *  1. A synthetic near-threshold pair is reported with the correct occurrence count, and stops
 *     being reported the moment it would actually reach `MIN_OCCURRENCE_THRESHOLD` — the exact
 *     instant `EchoService` picks it up instead, so the two never say something different about the
 *     same pair on the same screen.
 *  2. The counting agrees with #26/E-1b's mixed-valence pairing rule (`pairing-counting-rule.test.ts`
 *     is the reference for that rule against the engine itself; this file checks `ProgressService`
 *     applies the identical `isPairExcluded` predicate, not a hand-copy that could drift).
 *  3. Task 3's gate: once the diary already has `SURFACED_PATTERN_GATE` (3) surfaced patterns, no
 *     pair is computed or returned, regardless of whether one would otherwise qualify.
 */

import Database from 'better-sqlite3';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { encodeDateTime, nowUtc } from '../../src/db/codecs';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnFresh();
});
afterEach(async () => {
  await teardown(h);
});

interface Written {
  id: string;
  version: number;
}

/** Write an entry and settle its feelings, exactly as a client does (mirrors `pairing-counting-rule.test.ts`). */
async function write(text: string, feelings: string[]): Promise<Written> {
  const created = (
    await request(server()).post('/entries').send({ mode: 'freeform', raw_text: text }).expect(201)
  ).body as Written;

  return (
    await request(server())
      .patch(`/entries/${created.id}`)
      .send({ feeling_keys: feelings, version: created.version })
      .expect(200)
  ).body as Written;
}

/** Topics are extracted by keyword during recompute, not on write (same note as the sibling suite). */
async function recompute(): Promise<void> {
  await request(server()).get('/insights').expect(200);
}

interface EntryTopic {
  id: string;
  name: string;
}

async function readEntry(entryId: string): Promise<{ topics: EntryTopic[] }> {
  return (await request(server()).get(`/entries/${entryId}`).expect(200)).body as {
    topics: EntryTopic[];
  };
}

async function confirmPairings(
  entryId: string,
  pairings: Array<{ topic_id: string; feeling_key: string }>,
): Promise<void> {
  await request(server()).put(`/entries/${entryId}/topic-feelings`).send({ pairings }).expect(200);
}

interface ProgressPair {
  topic: string;
  feeling: string;
  occurrences: number;
  threshold: number;
}

interface Progress {
  topics_tracked: number;
  confirmed_entries: number;
  pairs: ProgressPair[];
  surfaced_pattern_count: number;
  surfaced_pattern_gate: number;
}

async function progressFor(entryId: string): Promise<Progress | null> {
  return (
    (await request(server()).get(`/entries/${entryId}/echo`).expect(200)).body as {
      progress: Progress | null;
    }
  ).progress;
}

async function echoesFor(entryId: string): Promise<Array<{ topic: string; feeling: string }>> {
  return (
    (await request(server()).get(`/entries/${entryId}/echo`).expect(200)).body as {
      echoes: Array<{ topic: string; feeling: string }>;
    }
  ).echoes;
}

// ---------------------------------------------------------------------------------------------
// 1. The synthetic near-threshold pair, and its disappearance once it graduates
// ---------------------------------------------------------------------------------------------

describe('a near-threshold pair (task 1)', () => {
  it('reports "2 of 3" for a pair the just-saved entry moved to two occurrences', async () => {
    await write('Another long day at work.', ['anxious']);
    await recompute(); // establishes the `work` topic and entry_topics for the first entry

    const second = await write('Work again, still on edge.', ['anxious']);
    // Deliberately no recompute between `second` and reading its progress — the whole point of
    // this endpoint is that it must be correct off the save path alone (C-06).
    const progress = await progressFor(second.id);

    expect(progress).not.toBeNull();
    expect(progress!.pairs).toEqual([
      { topic: 'work', feeling: 'anxious', occurrences: 2, threshold: 3 },
    ]);
    expect(progress!.confirmed_entries).toBe(2);
    expect(progress!.topics_tracked).toBeGreaterThanOrEqual(1);
    expect(progress!.surfaced_pattern_count).toBe(0);
    expect(progress!.surfaced_pattern_gate).toBe(3);
  });

  it('stops reporting a pair the moment this save would take it to the threshold', async () => {
    await write('Another long day at work.', ['anxious']);
    await recompute();
    await write('Work again, still on edge.', ['anxious']);
    await recompute(); // now `work`/`anxious` has two *recorded* occurrences

    // A third occurrence: the pair the previous test reported as "2 of 3" would now be 3 of 3 —
    // no longer below the threshold, so it must not appear here even though nothing has
    // recomputed yet and `patterns` does not carry it as a pattern either.
    const third = await write('Work, again, relentless.', ['anxious']);
    const progress = await progressFor(third.id);

    expect(progress).not.toBeNull();
    expect(progress!.pairs).toEqual([]);
  });

  it('keeps omitting the pair once it has actually surfaced, alongside its own echo', async () => {
    for (const text of [
      'Another long day at work.',
      'Work again, still on edge.',
      'Work, relentless.',
    ]) {
      await write(text, ['anxious']);
    }
    await recompute(); // work/anxious now has lifetime_count 3 and materialises as a pattern

    const fourth = await write('Work, yet again.', ['anxious']);
    const [progress, echoes] = await Promise.all([progressFor(fourth.id), echoesFor(fourth.id)]);

    // The pattern is already real, so the echo carries it —
    expect(echoes.find((e) => e.topic === 'work' && e.feeling === 'anxious')).toBeDefined();
    // — and the progress surface must not also show a "3 of 3"/"4 of 3" line for the same pair:
    // the two can never disagree about whether a pair is still "below threshold".
    expect(progress).not.toBeNull();
    expect(
      progress!.pairs.find((p) => p.topic === 'work' && p.feeling === 'anxious'),
    ).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------------------------
// 2. Consistency with #26/E-1b's mixed-valence pairing rule
// ---------------------------------------------------------------------------------------------

describe('consistency with the mixed-valence pairing rule (#26, E-1b)', () => {
  it('never counts an unconfirmed mixed-valence entry toward its own topic×feeling pairs', async () => {
    // Seed the `exercise`/`family` topic rows so `matchExistingTopics` can resolve them for a
    // brand-new, not-yet-recomputed entry (mirrors `pairing-counting-rule.test.ts`'s own setup).
    await write('Did some exercise and saw family today.', ['calm']);
    await recompute();

    const mixed = await write('Skipped my workout and visited my parents.', [
      'disappointed',
      'happy',
    ]);
    // No `PUT .../topic-feelings` at all — the pairing step is skipped entirely.
    const progress = await progressFor(mixed.id);

    expect(progress).not.toBeNull();
    expect(progress!.pairs).toEqual([]);
  });

  it('counts a mixed-valence entry toward exactly the pair it confirmed', async () => {
    await write('Did some exercise and saw family today.', ['calm']);
    await recompute();

    const firstMixed = await write('Skipped my workout and visited my parents.', [
      'disappointed',
      'happy',
    ]);
    await recompute();
    const entry = await readEntry(firstMixed.id);
    const exercise = entry.topics.find((t) => t.name === 'exercise')!;
    const family = entry.topics.find((t) => t.name === 'family')!;
    expect(exercise, 'exercise topic missing').toBeDefined();
    expect(family, 'family topic missing').toBeDefined();
    await confirmPairings(firstMixed.id, [
      { topic_id: exercise.id, feeling_key: 'disappointed' },
      { topic_id: family.id, feeling_key: 'happy' },
    ]);
    await recompute();

    const secondMixed = await write('Missed the gym again, then saw my parents.', [
      'disappointed',
      'happy',
    ]);
    await recompute(); // so `secondMixed` has its own `entry_topics` rows to pair against
    // `secondMixed` confirms its own pairing too — rule 2 excludes an entry from a pair only when
    // *that entry's own* confirmation is missing, not when some other entry's is.
    const secondEntry = await readEntry(secondMixed.id);
    const exercise2 = secondEntry.topics.find((t) => t.name === 'exercise')!;
    const family2 = secondEntry.topics.find((t) => t.name === 'family')!;
    await confirmPairings(secondMixed.id, [
      { topic_id: exercise2.id, feeling_key: 'disappointed' },
      { topic_id: family2.id, feeling_key: 'happy' },
    ]);

    const progress = await progressFor(secondMixed.id);
    expect(progress).not.toBeNull();
    const byPair = new Map(progress!.pairs.map((p) => [`${p.topic} ${p.feeling}`, p.occurrences]));
    expect(byPair.get('exercise disappointed')).toBe(2);
    expect(byPair.get('family happy')).toBe(2);
    // The cross pairs were never confirmed by either entry — same conservative default the engine
    // itself applies — so they must not appear at all, not even at zero.
    expect(byPair.has('exercise happy')).toBe(false);
    expect(byPair.has('family disappointed')).toBe(false);
  });
});

// ---------------------------------------------------------------------------------------------
// 3. Task 3's gate — hidden once the diary already has ≥3 surfaced patterns
// ---------------------------------------------------------------------------------------------

/**
 * Seeds three `patterns` rows directly, the same technique `entries-topic-feelings.test.ts` uses
 * for `entry_topics`/`entry_topic_feelings` — `ImmediateTestInference` never runs the real engine,
 * and building three genuine surfaced patterns through the live pipeline would mean fighting the
 * inverse-pattern and lift machinery for a fact this test does not otherwise care about (only the
 * row count `PatternsService#surfacedPatternCount()` reads). Foreign keys are off in this database
 * (`src/db/database.ts`), so the placeholder `topic_id` values below never need a real `topics`
 * row to satisfy a constraint — that pragma is per-connection, though, so it is set again here
 * rather than assumed inherited from the app's own connection.
 */
function seedSurfacedPatterns(count: number): void {
  const db = new Database(h.dbPath);
  try {
    db.pragma('foreign_keys = OFF');
    const now = encodeDateTime(nowUtc());
    const insert = db.prepare(
      `INSERT INTO patterns
         (id, topic_id, feeling_key, occurrence_count, narrative_text, suggestion_text, direction,
          first_detected_at, last_updated_at)
       VALUES (?, ?, ?, 3, 'placeholder narrative', 'placeholder suggestion', 'keep', ?, ?)`,
    );
    for (let i = 0; i < count; i += 1) {
      insert.run(randomUUID(), `topic-${i}`, 'calm', now, now);
    }
  } finally {
    db.close();
  }
}

describe('the ≥3 surfaced-patterns gate (task 3)', () => {
  it('reports zero pairs — and skips computing any — once 3 patterns are already surfaced', async () => {
    await write('Another long day at work.', ['anxious']);
    await recompute(); // establishes the `work` topic, before any seeding below

    // Seeded *after* the only recompute this test runs: `recomputePatterns()` rebuilds `patterns`
    // from what it can actually find in the diary and would withdraw (delete) these placeholder
    // rows on its very next run, since no real entry supports them. Nothing in the request this
    // test makes below (`GET /entries/:id/echo`) ever calls it (C-06), so the seed is safe here.
    seedSurfacedPatterns(3);

    const second = await write('Work again, still on edge.', ['anxious']);
    const progress = await progressFor(second.id);

    // Without the gate this would be a textbook "2 of 3" (see the first describe block above) —
    // the gate must suppress it regardless.
    expect(progress).not.toBeNull();
    expect(progress!.pairs).toEqual([]);
    expect(progress!.surfaced_pattern_count).toBe(3);
    expect(progress!.surfaced_pattern_gate).toBe(3);
    // The cheaper counters are still reported honestly — the client, not this endpoint, is the one
    // that decides to hide the section (see `ProgressOut.surfaced_pattern_count`'s doc comment).
    expect(progress!.confirmed_entries).toBe(2);
  });
});
