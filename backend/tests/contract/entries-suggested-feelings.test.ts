/**
 * Issue #66 — `EntriesService.analysisFor()` suppressed an analyser suggestion precisely when it
 * had already been applied to the entry, which is the *normal* case: the worker writes
 * `feeling_keys`/`feeling_source = 'suggested'` onto the entry itself before the API ever renders
 * a response (see `applyAnalysis` in `src/inference/worker.ts`, and the idempotent mirror of it in
 * `EntriesService.analyzeStoredEntry`). The old guard compared the entry's current feelings against
 * the job's proposed ones and suppressed whenever they were equal — true for *every* freshly
 * analysed entry, so `suggested_feelings` came back `[]` and the composer had nothing to
 * pre-select from.
 *
 * These tests reproduce that persisted state directly rather than mocking the API layer: a
 * completed `inference_jobs` row plus an entry whose `feeling_keys`/`feeling_source` already carry
 * the worker's own write, exactly the shape the orchestrator captured from the live system
 * (`GET /entries?date=...` returning `suggested_feelings: []`, `suggested_feeling: null` despite a
 * completed job). `applyWorkerAnalysis` below mirrors `applyAnalysis`'s writes rather than going
 * through `ImmediateTestInference` (which never writes an `inference_jobs` row at all, so it can't
 * exercise the `analysisFor` read path this bug lives in).
 */

import Database from 'better-sqlite3';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnFresh();
});
afterEach(async () => {
  await teardown(h);
});

interface EntryOut {
  id: string;
  version: number;
  feeling_key: string | null;
  feeling_keys: string[];
  feeling_source: string;
  suggested_feeling: { key: string; confidence: number } | null;
  suggested_feelings: Array<{ key: string; confidence: number }>;
  analysis_pending: boolean;
  entry_date: string;
}

/**
 * Writes exactly what the worker's `applyAnalysis` writes: the entry's `feeling_key`/
 * `feeling_source`/`entry_feelings` set to the analysis result, and a `completed` `inference_jobs`
 * row carrying the same result as `result_json` — the ground-truth shape captured from the live
 * system in issue #66. A direct `Database` handle against the harness's own file, same pattern as
 * `tests/e2e/series.test.ts`'s `backdate`.
 */
function applyWorkerAnalysis(
  entryId: string,
  feelings: Array<{ key: string; confidence: number }>,
  // The real worker only ever writes 'suggested' (it applies feelings while
  // `feeling_source = 'unset'`). Tests that need to simulate a *later* analysis run landing on an
  // entry the user has already confirmed/overridden pass that source explicitly, since this
  // helper writes the entry's feelings unconditionally rather than replaying the worker's own
  // `WHERE feeling_source = 'unset'` guard.
  feelingSource: 'suggested' | 'confirmed' | 'overridden' = 'suggested',
): void {
  const db = new Database(h.dbPath);
  const now = new Date().toISOString().replace('T', ' ').replace('Z', '').slice(0, 26);
  db.prepare(
    `UPDATE diary_entries SET feeling_key = ?, feeling_source = ?, updated_at = ?
     WHERE id = ?`,
  ).run(feelings[0].key, feelingSource, now, entryId);
  db.prepare('DELETE FROM entry_feelings WHERE entry_id = ?').run(entryId);
  const insertFeeling = db.prepare(
    'INSERT INTO entry_feelings (entry_id, feeling_key, position) VALUES (?, ?, ?)',
  );
  feelings.forEach((feeling, position) => insertFeeling.run(entryId, feeling.key, position));
  db.prepare(
    `INSERT INTO inference_jobs
     (id, kind, entry_id, status, result_json, error_text, attempts, created_at, started_at, completed_at)
     VALUES (?, 'entry_analysis', ?, 'completed', ?, NULL, 1, ?, ?, ?)`,
  ).run(
    randomUUID(),
    entryId,
    JSON.stringify({
      feeling_key: feelings[0].key,
      confidence: feelings[0].confidence,
      feelings,
    }),
    now,
    now,
    now,
  );
  db.close();
}

async function createEntry(raw_text: string): Promise<EntryOut> {
  return (await request(server()).post('/entries').send({ mode: 'freeform', raw_text }).expect(201))
    .body as EntryOut;
}

async function getEntry(entryId: string, date: string): Promise<EntryOut> {
  const listed = await request(server()).get(`/entries?date=${date}`).expect(200);
  const entry = (listed.body.entries as EntryOut[]).find((e) => e.id === entryId);
  if (!entry) throw new Error(`entry ${entryId} not found in GET /entries?date=${date}`);
  return entry;
}

describe('GET /entries -- suggested feelings the worker has already applied (#66)', () => {
  it('surfaces the analyser suggestion when the entry already carries it as feeling_source=suggested', async () => {
    const created = await createEntry(
      'Went for a long walking route this evening and felt genuinely calm and happy afterwards. ' +
        'Work had been stressful and anxious all day.',
    );

    // Ground truth from the live system: worker applies both feelings, job row completes with
    // both in `feelings`, feeling_source stays 'suggested'.
    applyWorkerAnalysis(created.id, [
      { key: 'happy', confidence: 0.9 },
      { key: 'anxious', confidence: 0.8 },
    ]);

    const entry = await getEntry(created.id, created.entry_date);

    expect(entry.feeling_source).toBe('suggested');
    expect(entry.feeling_keys.sort()).toEqual(['anxious', 'happy']);
    expect(entry.analysis_pending).toBe(false);

    // This is the assertion that failed against main: the old guard suppressed the suggestion
    // whenever it matched the entry's own feelings, which is always true right after the worker
    // runs, so both of these came back empty/null.
    expect(entry.suggested_feelings.length).toBeGreaterThan(0);
    expect(entry.suggested_feelings.map((f) => f.key).sort()).toEqual(['anxious', 'happy']);
    expect(entry.suggested_feeling).not.toBeNull();
    expect(entry.suggested_feeling?.key).toBe('happy');
  });

  it('still returns nothing to propose for an entry with no completed analysis', async () => {
    const created = await createEntry('Just a note, nothing more.');
    const entry = await getEntry(created.id, created.entry_date);
    expect(entry.suggested_feelings).toEqual([]);
    expect(entry.suggested_feeling).toBeNull();
  });
});

describe('GET /entries -- a real user choice is not re-suggested (regression)', () => {
  it('suppresses the suggestion once the user confirms exactly what the analyser proposed', async () => {
    const created = await createEntry('A calm evening.');
    applyWorkerAnalysis(created.id, [{ key: 'happy', confidence: 0.9 }]);

    const beforeConfirm = await getEntry(created.id, created.entry_date);
    expect(beforeConfirm.suggested_feelings.length).toBeGreaterThan(0);

    // Confirming exactly the suggested set stores feeling_source = 'confirmed' (#1's contract).
    const confirmed = (
      await request(server())
        .patch(`/entries/${created.id}`)
        .send({ feeling_keys: ['happy'], version: beforeConfirm.version })
        .expect(200)
    ).body as EntryOut;
    expect(confirmed.feeling_source).toBe('confirmed');

    const entry = await getEntry(created.id, created.entry_date);
    expect(entry.feeling_source).toBe('confirmed');
    // The analyser's own completed job still says "happy" — the same thing the user just
    // confirmed. That must not come back as a suggestion: the user has already spoken.
    expect(entry.suggested_feelings).toEqual([]);
    expect(entry.suggested_feeling).toBeNull();
  });

  it('suppresses the suggestion once the user overrides to feelings the analyser later re-proposes', async () => {
    const created = await createEntry('A tense morning.');
    applyWorkerAnalysis(created.id, [{ key: 'happy', confidence: 0.9 }]);
    const beforeOverride = await getEntry(created.id, created.entry_date);

    // Choosing something other than the suggestion stores feeling_source = 'overridden'.
    const overridden = (
      await request(server())
        .patch(`/entries/${created.id}`)
        .send({ feeling_keys: ['sad'], version: beforeOverride.version })
        .expect(200)
    ).body as EntryOut;
    expect(overridden.feeling_source).toBe('overridden');

    // A later analysis run happens to land on exactly what the user already chose. The entry's
    // feeling_source stays 'overridden' throughout, same as it would with the real worker's
    // `WHERE feeling_source = 'unset'` guard leaving a confirmed/overridden entry untouched.
    applyWorkerAnalysis(created.id, [{ key: 'sad', confidence: 0.6 }], 'overridden');

    const entry = await getEntry(created.id, created.entry_date);
    expect(entry.feeling_source).toBe('overridden');
    expect(entry.suggested_feelings).toEqual([]);
    expect(entry.suggested_feeling).toBeNull();
  });
});
