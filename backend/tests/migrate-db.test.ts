/**
 * Growing an existing diary to the grouped vocabulary.
 *
 * The risk this pins down is the one that matters: a migration is the only command in the project
 * that alters a real diary, so it must add reference data, backfill derived data, and touch
 * nothing the user wrote. `pre-grouped-vocabulary.db` is the golden fixture exactly as it stood
 * before this feature — a genuine pre-migration diary, not a reconstruction of one.
 */

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import Database from 'better-sqlite3';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { assertCompatible } from '../src/db/compatibility';
import { openDiary } from '../src/db/database';
import { FEELING_GROUP_SEED, FEELING_SEED } from '../src/db/feeling-vocabulary';
import { migrateDiary } from '../src/db/migrate';

const LEGACY = path.resolve(__dirname, 'fixtures/pre-grouped-vocabulary.db');

let dir: string;
let target: string;

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-migrate-'));
  target = path.join(dir, 'diary.db');
  fs.copyFileSync(LEGACY, target);
});

afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true });
});

function read<T>(query: string): T[] {
  const db = new Database(target, { readonly: true });
  try {
    return db.prepare(query).all() as T[];
  } finally {
    db.close();
  }
}

describe('migrateDiary', () => {
  it('turns a diary the backend refuses into one it can serve', () => {
    const before = openDiary(target);
    expect(() => assertCompatible(before)).toThrow(/feeling_groups/);
    before.close();

    migrateDiary(target);

    const after = openDiary(target);
    expect(() => assertCompatible(after)).not.toThrow();
    after.close();
  });

  it('installs the whole vocabulary, groups included', () => {
    migrateDiary(target);

    expect(
      read<{ key: string }>('SELECT "key" FROM feelings ORDER BY sort_order').map((r) => r.key),
    ).toEqual(FEELING_SEED.map((feeling) => feeling.key));
    expect(
      read<{ key: string }>('SELECT "key" FROM feeling_groups ORDER BY sort_order').map(
        (r) => r.key,
      ),
    ).toEqual(FEELING_GROUP_SEED.map((group) => group.key));
  });

  it('backfills each entry’s single feeling as the first of its set', () => {
    const before = read<{ id: string; feeling_key: string | null }>(
      'SELECT id, feeling_key FROM diary_entries',
    ).filter((row) => row.feeling_key !== null);
    expect(before.length).toBeGreaterThan(0);

    migrateDiary(target);

    const after = read<{ entry_id: string; feeling_key: string; position: number }>(
      'SELECT entry_id, feeling_key, position FROM entry_feelings',
    );
    expect(after).toHaveLength(before.length);
    for (const row of before) {
      const backfilled = after.find((f) => f.entry_id === row.id);
      expect(backfilled).toEqual({
        entry_id: row.id,
        feeling_key: row.feeling_key,
        position: 0,
      });
    }
  });

  it('leaves every entry the user wrote exactly as it was', () => {
    // Named columns rather than `SELECT *`: the migration is allowed to *add* a nullable column —
    // that is what "additive" means — and the claim under test is that it never alters a value the
    // user put there. A star select would fail on the new column and pass on a rewritten entry,
    // which is exactly backwards.
    const WRITTEN =
      'id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source, version';
    const before = read<Record<string, unknown>>(
      `SELECT ${WRITTEN} FROM diary_entries ORDER BY id`,
    );
    const answersBefore = read<Record<string, unknown>>(
      'SELECT * FROM guiding_question_answers ORDER BY id',
    );

    migrateDiary(target);

    expect(
      read<Record<string, unknown>>(`SELECT ${WRITTEN} FROM diary_entries ORDER BY id`),
    ).toEqual(before);

    // And the column it did add starts empty on every existing entry.
    expect(
      read<{ feeling_intensity: number | null }>(
        'SELECT feeling_intensity FROM diary_entries',
      ).every((row) => row.feeling_intensity === null),
    ).toBe(true);
    expect(
      read<Record<string, unknown>>('SELECT * FROM guiding_question_answers ORDER BY id'),
    ).toEqual(answersBefore);
  });

  it('is idempotent — running it twice changes nothing the second time', () => {
    migrateDiary(target);
    const once = {
      feelings: read<Record<string, unknown>>('SELECT * FROM feelings ORDER BY "key"'),
      groups: read<Record<string, unknown>>('SELECT * FROM feeling_groups ORDER BY "key"'),
      entryFeelings: read<Record<string, unknown>>(
        'SELECT * FROM entry_feelings ORDER BY entry_id, position',
      ),
    };

    const second = migrateDiary(target);
    expect(second.groupsInserted).toBe(0);
    expect(second.feelingsInserted).toBe(0);
    expect(second.entryFeelingsBackfilled).toBe(0);

    expect(read<Record<string, unknown>>('SELECT * FROM feelings ORDER BY "key"')).toEqual(
      once.feelings,
    );
    expect(read<Record<string, unknown>>('SELECT * FROM feeling_groups ORDER BY "key"')).toEqual(
      once.groups,
    );
    expect(
      read<Record<string, unknown>>('SELECT * FROM entry_feelings ORDER BY entry_id, position'),
    ).toEqual(once.entryFeelings);
  });

  it('refuses a path with no diary rather than creating one', () => {
    const missing = path.join(dir, 'nope.db');
    expect(() => migrateDiary(missing)).toThrow(/No diary at/);
    expect(fs.existsSync(missing)).toBe(false);
  });
});
