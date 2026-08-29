/**
 * E-1a task 5 — the mixed-valence example entry `seedExampleMixedValenceEntry` (`src/db/seed.ts`)
 * adds for client development.
 *
 * The safety property under test matters more than the entry's content: `seed()` runs on *every*
 * server boot (`db/database.provider.ts`), so the example entry must never be reachable from it —
 * writing a diary entry nobody wrote into every fresh diary a real user creates would be exactly
 * the silent surprise FR-022 exists to prevent.
 */

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { openDiary, type DiaryDatabase } from '../src/db/database';
import { initDiary } from '../src/db/init';
import { seed, seedExampleMixedValenceEntry } from '../src/db/seed';

let dir: string;
let dbPath: string;
let db: DiaryDatabase;

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-example-seed-'));
  dbPath = path.join(dir, 'diary.db');
  initDiary(dbPath);
  db = openDiary(dbPath);
});

afterEach(() => {
  db.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

function count(table: string): number {
  return (db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number }).n;
}

describe('seed() (the automatic, every-boot path) never writes the example entry', () => {
  it('leaves diary_entries empty on a fresh diary', () => {
    seed(db);
    expect(count('diary_entries')).toBe(0);
  });

  it('still leaves diary_entries empty even called repeatedly, mirroring seed()’s own no-op guarantee', () => {
    seed(db);
    seed(db);
    seed(db);
    expect(count('diary_entries')).toBe(0);
  });
});

describe('seedExampleMixedValenceEntry (explicit, developer-invoked only)', () => {
  it('writes one entry with a mixed feeling set and plausible suggested pairings', () => {
    const { entryId } = seedExampleMixedValenceEntry(db);

    const entry = db
      .prepare('SELECT feeling_key, feeling_source, mode FROM diary_entries WHERE id = ?')
      .get(entryId) as { feeling_key: string; feeling_source: string; mode: string };
    expect(entry.feeling_source).toBe('suggested');
    expect(entry.mode).toBe('freeform');

    const feelings = (
      db
        .prepare('SELECT feeling_key FROM entry_feelings WHERE entry_id = ? ORDER BY position')
        .all(entryId) as Array<{ feeling_key: string }>
    ).map((row) => row.feeling_key);
    // Mixed valence: one feeling from each side, which is the whole point of the example.
    expect(feelings).toEqual(['disappointed', 'grateful']);
    expect(entry.feeling_key).toBe(feelings[0]);

    const pairings = db
      .prepare(
        `SELECT t.name AS topic, etf.feeling_key, etf.source FROM entry_topic_feelings etf
         JOIN topics t ON t.id = etf.topic_id WHERE etf.entry_id = ? ORDER BY t.name`,
      )
      .all(entryId) as Array<{ topic: string; feeling_key: string; source: string }>;
    expect(pairings).toEqual([
      { topic: 'exercise', feeling_key: 'disappointed', source: 'suggested' },
      { topic: 'family', feeling_key: 'grateful', source: 'suggested' },
    ]);
  });

  it('is safe to call on a diary that already has the reference data seeded', () => {
    seed(db);
    expect(() => seedExampleMixedValenceEntry(db)).not.toThrow();
    expect(count('diary_entries')).toBe(1);
  });
});
