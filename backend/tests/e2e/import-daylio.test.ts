/**
 * The Daylio CSV import, end to end (L-1b, #35): `POST /import/daylio/dry-run` (report, no write)
 * and `POST /import/daylio/commit` (write, idempotent by content hash), against
 * `tests/fixtures/daylio-sample.csv` — see `tests/fixtures/README.md` for what that file contains
 * and why, and `../../src/import/daylio-mood-map.ts` for the mapping table's sources.
 *
 * Booted via `startOnLoopback` (`bootOnFresh`, through `tests/helpers/app.ts`) rather than a
 * standalone dev server — these are the "curl the endpoints" steps the issue's Verification
 * section asks for, made into a real HTTP round trip against the actual Nest app.
 */

import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import * as path from 'node:path';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { encodeDateTime, nowUtc } from '../../src/db/codecs';
import { bootOnFresh, teardown, type Harness } from '../helpers/app';

const FIXTURE_PATH = path.resolve(__dirname, '../fixtures/daylio-sample.csv');
const FIXTURE_BUFFER = fs.readFileSync(FIXTURE_PATH);
const HASH_PATTERN = /^[0-9a-f]{64}$/;

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnFresh();
});
afterEach(async () => {
  await teardown(h);
});

function dryRun() {
  return request(server())
    .post('/import/daylio/dry-run')
    .attach('file', FIXTURE_BUFFER, 'daylio.csv');
}

function commit(reportHash: string) {
  return request(server())
    .post('/import/daylio/commit')
    .attach('file', FIXTURE_BUFFER, 'daylio.csv')
    .field('report_hash', reportHash);
}

/** Writes a `diary_entries` row directly, standing in for an entry the user wrote some other way —
 *  the normal `POST /entries` 30-day backdate cap (#36) cannot reach the fixture's July dates, so a
 *  collision has to be seeded below the API, the same technique `export.test.ts` uses for state the
 *  API cannot produce directly. */
function insertExistingEntry(entryDate: string, rawText: string): void {
  const db = new Database(h.dbPath);
  try {
    const now = encodeDateTime(nowUtc());
    db.prepare(
      `INSERT INTO diary_entries
       (id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source, version, origin)
       VALUES (?, ?, ?, ?, 'freeform', ?, NULL, 'unset', 1, 'app')`,
    ).run('existing-entry-1', now, now, entryDate, rawText);
  } finally {
    db.close();
  }
}

describe('POST /import/daylio/dry-run', () => {
  it('reports the fixture accurately without writing anything', async () => {
    const res = await dryRun().expect(200);
    const body = res.body;

    expect(body.content_hash).toMatch(HASH_PATTERN);
    expect(body.report_hash).toMatch(HASH_PATTERN);
    expect(body.total_rows).toBe(17);
    expect(body.parseable_count).toBe(17);
    expect(body.importable_count).toBe(16); // every row except the "fantastic" custom mood
    expect(body.unparseable_rows).toEqual([]);
    expect(body.already_imported).toBe(false);
    expect(body.previous_import).toBeNull();
    expect(body.date_range).toEqual({ start: '2026-07-01', end: '2026-07-16' });
    expect(body.collisions).toEqual([]);

    // The mapping table this ticket proposes, exactly as used against the fixture's five moods.
    expect(body.mood_mapping).toEqual([
      { daylio_mood: 'awful', feeling_key: 'depressed' },
      { daylio_mood: 'bad', feeling_key: 'sad' },
      { daylio_mood: 'good', feeling_key: 'content' },
      { daylio_mood: 'meh', feeling_key: 'neutral' },
      { daylio_mood: 'rad', feeling_key: 'happy' },
    ]);

    // The one custom/renamed mood in the fixture (row 13, "fantastic") — skipped and reported,
    // never guessed at.
    expect(body.unmapped_moods).toEqual([{ mood: 'fantastic', count: 1, sample_rows: [13] }]);
  });

  it('never writes an entry', async () => {
    await dryRun().expect(200);
    const res = await request(server()).get('/entries?date=2026-07-01').expect(200);
    expect(res.body.entries).toEqual([]);
  });

  it('flags a row whose date and exact text already exist as a collision', async () => {
    // Row 1 (no note_title): raw_text is the note as-is — see `composeRawText`.
    insertExistingEntry('2026-07-01', 'Great start to the day.');

    const res = await dryRun().expect(200);
    expect(res.body.collisions).toEqual([
      {
        row: 1,
        entry_date: '2026-07-01',
        reason: 'An entry with this date and text already exists in the diary.',
      },
    ]);
    // Still counted as importable — a collision is informational, not a reason to drop the row
    // (see DaylioImportService.commit's doc comment).
    expect(res.body.importable_count).toBe(16);
  });

  it('rejects a request with no file, 422', async () => {
    const res = await request(server()).post('/import/daylio/dry-run').expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('rejects a file that is not a Daylio export (wrong columns), 422', async () => {
    const res = await request(server())
      .post('/import/daylio/dry-run')
      .attach('file', Buffer.from('name,value\nfoo,bar\n'), 'not-daylio.csv')
      .expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });
});

describe('POST /import/daylio/commit', () => {
  it('writes every mapped row, skips the unmapped one, and reports both counts', async () => {
    const report = (await dryRun().expect(200)).body;
    const res = await commit(report.report_hash).expect(200);

    expect(res.body).toEqual({
      idempotent: false,
      imported_count: 16,
      skipped_unmapped_count: 1,
      entry_ids: expect.arrayContaining([expect.any(String)]),
      content_hash: report.content_hash,
      previous_import: null,
    });
    expect(res.body.entry_ids).toHaveLength(16);
  });

  it('writes entries with the CSV date, the mapped feeling as overridden, and daylio_import origin', async () => {
    const report = (await dryRun().expect(200)).body;
    await commit(report.report_hash).expect(200);

    const res = await request(server()).get('/entries?date=2026-07-06').expect(200);
    expect(res.body.entries).toHaveLength(1);
    const entry = res.body.entries[0];
    expect(entry.entry_date).toBe('2026-07-06');
    expect(entry.created_at).toBe('2026-07-06T07:45:00.000000'); // 7:45 am
    expect(entry.feeling_key).toBe('depressed'); // awful -> depressed
    expect(entry.feeling_keys).toEqual(['depressed']);
    expect(entry.feeling_source).toBe('overridden');
    expect(entry.origin).toBe('daylio_import');
    // note_title + note (row 7 has both) composed into raw_text.
    expect(entry.raw_text).toBe('Not feeling it\n\nWoke up with a migraine, awful morning.');
  });

  it('reads midnight ("12:00 am") as the start of the entry_date it names, not the previous day', async () => {
    const report = (await dryRun().expect(200)).body;
    await commit(report.report_hash).expect(200);

    const res = await request(server()).get('/entries?date=2026-07-05').expect(200);
    expect(res.body.entries).toHaveLength(1);
    expect(res.body.entries[0].created_at).toBe('2026-07-05T00:00:00.000000');
  });

  it('links activities as topics, canonicalised, surviving a pattern recompute', async () => {
    const report = (await dryRun().expect(200)).body;
    await commit(report.report_hash).expect(200);

    // GET /insights recomputes patterns, which deletes and re-derives every *keyword*-extracted
    // topic link from raw_text — exercising exactly the hazard 'import' provenance exists to avoid
    // (see TopicsService.linkTopics's doc comment).
    await request(server()).get('/insights').expect(200);

    const exported = await request(server()).get('/export?format=json').expect(200);
    const entries = exported.body.entries as Array<{
      date: string;
      topics: Array<{ topic: string }>;
    }>;
    const day1 = entries.find(
      (e) => e.date === '2026-07-01' && e.topics.some((t) => t.topic === 'coffee'),
    );
    expect(day1).toBeDefined();
    expect(day1!.topics.map((t) => t.topic).sort()).toEqual(['coffee', 'exercise']);
  });

  it('does not write an entry for the unmapped custom-mood row', async () => {
    const report = (await dryRun().expect(200)).body;
    await commit(report.report_hash).expect(200);

    const res = await request(server()).get('/entries?date=2026-07-12').expect(200);
    expect(res.body.entries).toEqual([]);
  });

  it('a second commit of the same file is idempotent: no-op, clearly reported, no duplicate entries', async () => {
    const report = (await dryRun().expect(200)).body;
    const first = await commit(report.report_hash).expect(200);
    expect(first.body.idempotent).toBe(false);
    expect(first.body.imported_count).toBe(16);

    const second = await commit(report.report_hash).expect(200);
    expect(second.body.idempotent).toBe(true);
    expect(second.body.imported_count).toBe(0);
    expect(second.body.entry_ids).toEqual([]);
    expect(second.body.previous_import).toEqual({
      imported_at: expect.any(String),
      entry_count: 16,
    });

    const rerunDryRun = await dryRun().expect(200);
    expect(rerunDryRun.body.already_imported).toBe(true);
    expect(rerunDryRun.body.previous_import).toEqual({
      imported_at: expect.any(String),
      entry_count: 16,
    });

    const totalAfterBoth = await request(server()).get('/entries?date=2026-07-06').expect(200);
    expect(totalAfterBoth.body.entries).toHaveLength(1); // still one, not two
  });

  it('rejects a report_hash that does not match a fresh dry-run of the file, 422', async () => {
    const res = await commit('0'.repeat(64)).expect(422);
    expect(res.body.error.code).toBe('validation_error');

    const afterEntries = await request(server()).get('/entries?date=2026-07-01').expect(200);
    expect(afterEntries.body.entries).toEqual([]); // the rejected commit wrote nothing
  });

  it('rejects a malformed report_hash, 422', async () => {
    const res = await request(server())
      .post('/import/daylio/commit')
      .attach('file', FIXTURE_BUFFER, 'daylio.csv')
      .field('report_hash', 'not-a-hash')
      .expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('rejects a request with no file, 422', async () => {
    const res = await request(server())
      .post('/import/daylio/commit')
      .field('report_hash', '0'.repeat(64))
      .expect(422);
    expect(res.body.error.code).toBe('validation_error');
  });

  it('patterns compute over imported entries: work co-occurring with sad clears the threshold', async () => {
    const report = (await dryRun().expect(200)).body;
    await commit(report.report_hash).expect(200);

    // "work" appears on 6 of the fixture's 17 days, and 5 of those 6 are `bad` -> `sad` — see
    // tests/fixtures/README.md's table. The fixture's dates are already outside the 30-day
    // recency window by the time this test can possibly run (2026-08-15 is the last date within
    // 30 days of the earliest committable run of this suite), so this checks lifetime evidence
    // rather than the windowed "active" count, which only grows more true as real time passes.
    const res = await request(server()).get('/insights').expect(200);
    const patterns = res.body.patterns as Array<{
      topic: string;
      feeling: string;
      lifetime_count: number;
    }>;
    const workSad = patterns.find((p) => p.topic === 'work' && p.feeling === 'sad');
    expect(workSad).toBeDefined();
    expect(workSad!.lifetime_count).toBeGreaterThanOrEqual(5);
  });
});
