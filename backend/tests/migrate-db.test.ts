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
import { DEFAULT_USER_ID } from '../src/auth/default-user';
import { assertCompatible } from '../src/db/compatibility';
import { encodeBool, encodeJson } from '../src/db/codecs';
import { openDiary } from '../src/db/database';
import { FEELING_GROUP_SEED, FEELING_SEED } from '../src/db/feeling-vocabulary';
import { migrateDiary } from '../src/db/migrate';
import { SCHEMA_STATEMENTS } from '../src/db/schema';
import { GUIDING_QUESTIONS } from '../src/db/seed';

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
    // Same reasoning as `WRITTEN` above, extended to this table by M-1b (#134): it now gains its
    // own `user_id` column, so `SELECT *` here would fail the instant this migration adds it.
    const ANSWER_WRITTEN =
      'id, entry_id, question_key, question_text_snapshot, answer_text, order_index';
    const answersBefore = read<Record<string, unknown>>(
      `SELECT ${ANSWER_WRITTEN} FROM guiding_question_answers ORDER BY id`,
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
      read<Record<string, unknown>>(
        `SELECT ${ANSWER_WRITTEN} FROM guiding_question_answers ORDER BY id`,
      ),
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

describe('migrateDiary — E-1a: the mixed-valence pairing table', () => {
  it('adds entry_topic_feelings, empty, without touching anything the user wrote', () => {
    const before = openDiary(target);
    expect(() => assertCompatible(before)).toThrow(/entry_topic_feelings/);
    before.close();

    const writtenBefore = read<Record<string, unknown>>(
      `SELECT id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source,
              version FROM diary_entries ORDER BY id`,
    );

    migrateDiary(target);

    expect(read<{ n: number }>('SELECT COUNT(*) AS n FROM entry_topic_feelings')[0].n).toBe(0);
    expect(
      read<Record<string, unknown>>(
        `SELECT id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source,
                version FROM diary_entries ORDER BY id`,
      ),
    ).toEqual(writtenBefore);

    const after = openDiary(target);
    expect(() => assertCompatible(after)).not.toThrow();
    after.close();
  });

  it('is idempotent — creating it twice is the same as creating it once', () => {
    migrateDiary(target);
    migrateDiary(target);
    expect(read<{ n: number }>('SELECT COUNT(*) AS n FROM entry_topic_feelings')[0].n).toBe(0);
  });
});

describe('migrateDiary — #60: the Steady group valence split', () => {
  /**
   * A diary that already went through the grouped-vocabulary migration, at the valence scheme
   * `feeling-vocabulary.ts` carried before #60: every feeling in "Steady", `calm`/`content`/
   * `relaxed`/`focused`/`curious` included, inherited the group's `neutral` valence. This is the
   * shape a real user's diary is in today, and it is what proves the migration *updates* an
   * existing row rather than only inserting new ones — `pre-grouped-vocabulary.db` above predates
   * the grouped vocabulary entirely, so it never exercises the update path for these five keys.
   */
  function buildPreSplitDiary(targetPath: string): void {
    const raw = new Database(targetPath);
    // M-1b (#134): `SCHEMA_STATEMENTS` now gives `diary_entries` a `user_id` that defaults to and
    // references `DEFAULT_USER_ID`, but this helper writes an entry before any `users` row exists
    // — better-sqlite3 defaults a fresh connection's `foreign_keys` to on, so without this the
    // insert below would fail the same way `migrate.ts`'s own connection would (see its comment).
    raw.pragma('foreign_keys = OFF');
    try {
      raw.exec('BEGIN');
      for (const statement of SCHEMA_STATEMENTS) raw.exec(statement);
      raw.exec('COMMIT');

      const insertGroup = raw.prepare(
        'INSERT INTO feeling_groups ("key", label, valence, sort_order) VALUES (?, ?, ?, ?)',
      );
      insertGroup.run('uplifted', 'Uplifted', 'positive', 0);
      insertGroup.run('steady', 'Steady', 'neutral', 1);
      insertGroup.run('tense', 'Tense', 'negative', 2);
      insertGroup.run('low', 'Low', 'negative', 3);

      const insertFeeling = raw.prepare(
        'INSERT INTO feelings ("key", label, valence, group_key, sort_order) VALUES (?, ?, ?, ?, ?)',
      );
      insertFeeling.run('happy', 'Happy', 'positive', 'uplifted', 0);
      const preSplitSteady = [
        'neutral',
        'calm',
        'content',
        'relaxed',
        'focused',
        'curious',
        'indifferent',
      ];
      preSplitSteady.forEach((key, index) =>
        insertFeeling.run(key, key, 'neutral', 'steady', 100 + index),
      );
      insertFeeling.run('sad', 'Sad', 'negative', 'low', 300);

      const stamp = '2026-01-01 00:00:00.000000';
      raw
        .prepare(
          `INSERT INTO diary_entries
             (id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source, version)
           VALUES ('e1', ?, ?, '2026-01-01', 'freeform', 'Tea and a quiet evening.', 'calm', 'confirmed', 1)`,
        )
        .run(stamp, stamp);
    } finally {
      raw.close();
    }
  }

  it('updates an existing row to the new per-feeling valence, without touching what the user wrote', () => {
    const preSplitDir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-pre-split-'));
    const preSplitPath = path.join(preSplitDir, 'diary.db');
    try {
      buildPreSplitDiary(preSplitPath);

      const report = migrateDiary(preSplitPath);
      // The five overridden feelings, plus `neutral` and `indifferent`, already existed and were
      // refreshed in place — not reinserted.
      expect(report.feelingsUpdated).toBeGreaterThanOrEqual(7);

      const db = new Database(preSplitPath, { readonly: true });
      try {
        const steady = db
          .prepare('SELECT "key", valence FROM feelings WHERE group_key = ? ORDER BY "key"')
          .all('steady') as Array<{ key: string; valence: string }>;
        expect(Object.fromEntries(steady.map((row) => [row.key, row.valence]))).toEqual({
          calm: 'positive',
          content: 'positive',
          curious: 'positive',
          focused: 'positive',
          indifferent: 'neutral',
          neutral: 'neutral',
          relaxed: 'positive',
        });
        // The group itself is untouched — this is a per-feeling override, not a regrouping.
        const group = db
          .prepare('SELECT valence FROM feeling_groups WHERE "key" = ?')
          .get('steady') as { valence: string };
        expect(group.valence).toBe('neutral');

        // No data loss: the entry the user wrote, and the feeling it points at, are exactly as
        // they were before the migration ran.
        const entry = db
          .prepare('SELECT feeling_key, raw_text, version FROM diary_entries WHERE id = ?')
          .get('e1') as { feeling_key: string; raw_text: string; version: number };
        expect(entry).toEqual({
          feeling_key: 'calm',
          raw_text: 'Tea and a quiet evening.',
          version: 1,
        });
      } finally {
        db.close();
      }
    } finally {
      fs.rmSync(preSplitDir, { recursive: true, force: true });
    }
  });

  it('is idempotent — a second run leaves the split exactly as the first left it', () => {
    const preSplitDir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-pre-split-idem-'));
    const preSplitPath = path.join(preSplitDir, 'diary.db');
    try {
      buildPreSplitDiary(preSplitPath);
      migrateDiary(preSplitPath);

      const db = new Database(preSplitPath, { readonly: true });
      const once = db.prepare('SELECT * FROM feelings ORDER BY "key"').all();
      db.close();

      const second = migrateDiary(preSplitPath);
      expect(second.feelingsInserted).toBe(0);

      const db2 = new Database(preSplitPath, { readonly: true });
      const twice = db2.prepare('SELECT * FROM feelings ORDER BY "key"').all();
      db2.close();
      expect(twice).toEqual(once);
    } finally {
      fs.rmSync(preSplitDir, { recursive: true, force: true });
    }
  });
});

describe('migrateDiary — #95: guiding-question copy refresh', () => {
  /**
   * A diary that predates #14's copy shortening: `general_feeling` still carries the old,
   * long-form prompt. It also carries a `category`, `trigger_keywords` and `is_mandatory` that
   * deliberately disagree with the current library entry, so a test can prove those three are
   * left alone while only `prompt_text` is refreshed — the identity/presentation split #95 draws.
   *
   * One entry answers `general_feeling` under the old wording, exactly as a real user's diary
   * would have one: this is what proves the fix is safe, not just that it runs.
   */
  const OLD_PROMPT =
    'Since your last entry—or in the last few hours—what happened? What were you doing, where ' +
    'were you, and who was around?';
  const OLD_CATEGORY = 'legacy_general';
  const OLD_KEYWORDS = ['legacy_keyword'];
  const OLD_MANDATORY = false;

  function buildPreCopyRefreshDiary(targetPath: string): { entryId: string; answerId: string } {
    const raw = new Database(targetPath);
    // M-1b (#134): see the matching comment in `buildPreSplitDiary` above.
    raw.pragma('foreign_keys = OFF');
    try {
      raw.exec('BEGIN');
      for (const statement of SCHEMA_STATEMENTS) raw.exec(statement);
      raw.exec('COMMIT');

      raw
        .prepare(
          `INSERT INTO guiding_questions ("key", category, prompt_text, trigger_keywords, is_mandatory)
           VALUES (?, ?, ?, ?, ?)`,
        )
        .run(
          'general_feeling',
          OLD_CATEGORY,
          OLD_PROMPT,
          encodeJson(OLD_KEYWORDS),
          encodeBool(OLD_MANDATORY),
        );

      const stamp = '2026-01-01 00:00:00.000000';
      const entryId = 'e1';
      raw
        .prepare(
          `INSERT INTO diary_entries
             (id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source, version)
           VALUES (?, ?, ?, '2026-01-01', 'guided', ?, NULL, 'unset', 1)`,
        )
        .run(entryId, stamp, stamp, `${OLD_PROMPT}\nA rough morning.`);

      const answerId = 'a1';
      raw
        .prepare(
          `INSERT INTO guiding_question_answers
             (id, entry_id, question_key, question_text_snapshot, answer_text, order_index)
           VALUES (?, ?, 'general_feeling', ?, 'A rough morning.', 0)`,
        )
        .run(answerId, entryId, OLD_PROMPT);

      return { entryId, answerId };
    } finally {
      raw.close();
    }
  }

  it('refreshes prompt_text on an existing question without touching past answers’ snapshots', () => {
    const dirForTest = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-copy-refresh-'));
    const targetPath = path.join(dirForTest, 'diary.db');
    try {
      const { answerId } = buildPreCopyRefreshDiary(targetPath);
      const currentPrompt = GUIDING_QUESTIONS.find(([key]) => key === 'general_feeling')?.[2];
      expect(currentPrompt).toBeDefined();
      expect(currentPrompt).not.toBe(OLD_PROMPT);

      const report = migrateDiary(targetPath);
      expect(report.guidingQuestionsUpdated).toBeGreaterThanOrEqual(1);

      const db = new Database(targetPath, { readonly: true });
      try {
        // The question row now carries the current, shortened copy — the whole point of #95.
        const question = db
          .prepare(
            'SELECT category, prompt_text, trigger_keywords, is_mandatory FROM guiding_questions WHERE "key" = ?',
          )
          .get('general_feeling') as {
          category: string;
          prompt_text: string;
          trigger_keywords: string;
          is_mandatory: number;
        };
        expect(question.prompt_text).toBe(currentPrompt);

        // Category, trigger_keywords and is_mandatory are identity/behaviour, not presentation —
        // #95 deliberately leaves them alone, so the diary's disagreeing values survive the
        // migration unchanged.
        expect(question.category).toBe(OLD_CATEGORY);
        expect(JSON.parse(question.trigger_keywords)).toEqual(OLD_KEYWORDS);
        expect(question.is_mandatory).toBe(encodeBool(OLD_MANDATORY));

        // The past answer's snapshot is untouched: it still reads exactly the wording the user
        // was actually asked under, regardless of what the question now says.
        const answer = db
          .prepare(
            'SELECT question_text_snapshot, answer_text FROM guiding_question_answers WHERE id = ?',
          )
          .get(answerId) as { question_text_snapshot: string; answer_text: string };
        expect(answer.question_text_snapshot).toBe(OLD_PROMPT);
        expect(answer.answer_text).toBe('A rough morning.');
      } finally {
        db.close();
      }
    } finally {
      fs.rmSync(dirForTest, { recursive: true, force: true });
    }
  });

  it('is idempotent — a second run leaves the refreshed copy exactly as the first left it', () => {
    const dirForTest = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-copy-refresh-idem-'));
    const targetPath = path.join(dirForTest, 'diary.db');
    try {
      buildPreCopyRefreshDiary(targetPath);
      migrateDiary(targetPath);

      const db = new Database(targetPath, { readonly: true });
      const once = db.prepare('SELECT * FROM guiding_questions ORDER BY "key"').all();
      db.close();

      migrateDiary(targetPath);

      const db2 = new Database(targetPath, { readonly: true });
      const twice = db2.prepare('SELECT * FROM guiding_questions ORDER BY "key"').all();
      db2.close();
      expect(twice).toEqual(once);
    } finally {
      fs.rmSync(dirForTest, { recursive: true, force: true });
    }
  });
});

describe('migrateDiary — M-1a: multi-tenant identity (#45)', () => {
  /**
   * `target` (from the top-level `beforeEach`) is a copy of `pre-grouped-vocabulary.db` — a real
   * pre-migration diary that already carries 8 diary entries, 2 topics and 2 materialised patterns,
   * plus the rows that hang off them (`entry_topics`, `pattern_entries`,
   * `guiding_question_answers`). It predates `users`/`sessions` entirely, exactly the shape a real
   * developer's diary is in today — this is "a copy of the existing dev DB" the acceptance
   * criteria ask for, without touching the real one at `~/projects/find-my-patterns/data/diary.db`.
   */
  const CONTENT_TABLES = [
    'diary_entries',
    'topics',
    'patterns',
    'entry_topics',
    'pattern_entries',
    'guiding_question_answers',
  ];

  function rowCounts(dbPath: string): Record<string, number> {
    const db = new Database(dbPath, { readonly: true });
    try {
      return Object.fromEntries(
        CONTENT_TABLES.map((table) => [
          table,
          (db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number }).n,
        ]),
      );
    } finally {
      db.close();
    }
  }

  it('adds users and sessions, and the default user, without losing a single row the user wrote', () => {
    const before = openDiary(target);
    expect(() => assertCompatible(before)).toThrow(/users/);
    before.close();
    const countsBefore = rowCounts(target);
    expect(countsBefore.diary_entries).toBeGreaterThan(0);
    expect(countsBefore.topics).toBeGreaterThan(0);
    expect(countsBefore.patterns).toBeGreaterThan(0);

    migrateDiary(target);

    expect(rowCounts(target)).toEqual(countsBefore);

    const users = read<{ id: string; email: string; password_hash: string }>(
      'SELECT id, email, password_hash FROM users',
    );
    expect(users).toEqual([
      {
        id: DEFAULT_USER_ID,
        email: 'owner@default-user.invalid',
        password_hash: 'disabled:no-password-set',
      },
    ]);
    expect(read<{ n: number }>('SELECT COUNT(*) AS n FROM sessions')[0].n).toBe(0);

    const after = openDiary(target);
    expect(() => assertCompatible(after)).not.toThrow();
    after.close();
  });

  it('is idempotent — running it again leaves the one default user exactly as it was', () => {
    migrateDiary(target);
    const once = read<Record<string, unknown>>('SELECT * FROM users');

    migrateDiary(target);
    expect(read<Record<string, unknown>>('SELECT * FROM users')).toEqual(once);
  });
});

describe('migrateDiary — M-2: server-side entitlements (#47)', () => {
  it('adds an empty entitlements table without backfilling a row for the default user', () => {
    const before = openDiary(target);
    expect(() => assertCompatible(before)).toThrow(/users/);
    before.close();

    migrateDiary(target);

    // Unlike `users`, no row is inserted for anyone — see `schema.ts`'s comment on this table:
    // absence already reads as free through `EntitlementsService#getEntitlement`, so there is
    // nothing to backfill for a diary that has never recorded a purchase.
    expect(read<{ n: number }>('SELECT COUNT(*) AS n FROM entitlements')[0].n).toBe(0);

    const after = openDiary(target);
    expect(() => assertCompatible(after)).not.toThrow();
    after.close();
  });

  it('is idempotent — running it twice leaves entitlements empty both times', () => {
    migrateDiary(target);
    migrateDiary(target);
    expect(read<{ n: number }>('SELECT COUNT(*) AS n FROM entitlements')[0].n).toBe(0);
  });

  it('lets the default user hold an entitlement once migrated, with the foreign key to users intact', () => {
    migrateDiary(target);
    const db = new Database(target);
    db.prepare(
      `INSERT INTO entitlements (user_id, tier, source, expires_at, updated_at)
       VALUES (?, 'premium', 'manual', NULL, '2026-01-01 00:00:00.000000')`,
    ).run(DEFAULT_USER_ID);
    db.close();

    const after = openDiary(target);
    expect(() => assertCompatible(after)).not.toThrow();
    after.close();

    const check = new Database(target, { readonly: true });
    const row = check
      .prepare('SELECT tier FROM entitlements WHERE user_id = ?')
      .get(DEFAULT_USER_ID) as { tier: string };
    check.close();
    expect(row.tier).toBe('premium');
  });
});

describe('migrateDiary — M-1b: user_id columns, backfill and indexes (#134)', () => {
  /**
   * Every table `schema.ts`'s M-1b note classifies as user data. `target` (the top-level
   * `beforeEach`'s copy of `pre-grouped-vocabulary.db`) predates every one of them except the six
   * this fixture already carries content in — `diary_entries`, `topics`, `patterns`,
   * `entry_topics`, `pattern_entries`, `guiding_question_answers` — plus the always-empty
   * `inference_jobs`. The rest (`entry_feelings`, `pattern_withdrawals`, `diary_meta`,
   * `experiments`, `entry_topic_feelings`, `csv_imports`) do not exist in this fixture at all, so
   * this is also the strongest test available that a genuinely old diary — one missing a table
   * outright, not merely missing a column on one it already has — still ends up with every table
   * correctly owned.
   */
  const USER_DATA_TABLES = [
    'topics',
    'diary_entries',
    'entry_feelings',
    'guiding_question_answers',
    'entry_topics',
    'patterns',
    'pattern_entries',
    'pattern_withdrawals',
    'experiments',
    'inference_jobs',
    'entry_topic_feelings',
    'csv_imports',
  ];
  const CONTENT_BEARING_TABLES = [
    'diary_entries',
    'topics',
    'patterns',
    'entry_topics',
    'pattern_entries',
    'guiding_question_answers',
  ];

  function rowCounts(dbPath: string, tables: string[]): Record<string, number> {
    const db = new Database(dbPath, { readonly: true });
    try {
      return Object.fromEntries(
        tables.map((table) => [
          table,
          (db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number }).n,
        ]),
      );
    } finally {
      db.close();
    }
  }

  it('adds user_id to every user-data table without losing or moving a single row', () => {
    const countsBefore = rowCounts(target, CONTENT_BEARING_TABLES);
    expect(countsBefore.diary_entries).toBeGreaterThan(0);
    expect(countsBefore.topics).toBeGreaterThan(0);
    expect(countsBefore.patterns).toBeGreaterThan(0);
    expect(countsBefore.entry_topics).toBeGreaterThan(0);
    expect(countsBefore.pattern_entries).toBeGreaterThan(0);
    expect(countsBefore.guiding_question_answers).toBeGreaterThan(0);

    migrateDiary(target);

    // Acceptance criterion: every table's row count unchanged.
    expect(rowCounts(target, CONTENT_BEARING_TABLES)).toEqual(countsBefore);

    // Acceptance criterion: every existing row owned by the default user, on every table this
    // fixture actually has content in, plus the always-empty `inference_jobs`.
    const db = new Database(target, { readonly: true });
    try {
      for (const table of USER_DATA_TABLES) {
        const rows = db.prepare(`SELECT user_id FROM ${table}`).all() as Array<{
          user_id: string;
        }>;
        for (const row of rows) {
          expect(row.user_id, `${table}.user_id`).toBe(DEFAULT_USER_ID);
        }
      }
      // `diary_meta` did not exist in this fixture at all, so the migration created it fresh —
      // nothing to backfill, but it must exist under its new composite key.
      const diaryMetaColumns = db
        .prepare(`SELECT name FROM pragma_table_info('diary_meta')`)
        .all() as Array<{ name: string }>;
      expect(diaryMetaColumns.map((c) => c.name).sort()).toEqual(['key', 'user_id', 'value']);
    } finally {
      db.close();
    }

    const after = openDiary(target);
    expect(() => assertCompatible(after)).not.toThrow();
    after.close();
  });

  it('is idempotent — running it twice leaves ownership exactly as the first run left it', () => {
    migrateDiary(target);
    const once = USER_DATA_TABLES.reduce<Record<string, unknown[]>>((acc, table) => {
      acc[table] = read<Record<string, unknown>>(`SELECT * FROM ${table} ORDER BY rowid`);
      return acc;
    }, {});

    migrateDiary(target);

    for (const table of USER_DATA_TABLES) {
      expect(read<Record<string, unknown>>(`SELECT * FROM ${table} ORDER BY rowid`)).toEqual(
        once[table],
      );
    }
  });

  it('lets a second user hold their own diary_meta row under the same key, once one exists', () => {
    migrateDiary(target);
    const db = new Database(target);
    const secondUserId = '00000000-0000-0000-0000-000000000002';
    db.prepare(`INSERT INTO users (id, email, password_hash, created_at) VALUES (?, ?, ?, ?)`).run(
      secondUserId,
      'second@example.invalid',
      'disabled:no-password-set',
      '2026-01-01 00:00:00.000000',
    );
    db.prepare(
      `INSERT INTO diary_meta (user_id, "key", value) VALUES (?, 'pattern_echo_log', ?)`,
    ).run(DEFAULT_USER_ID, '{}');
    // Same key, different owner — this is exactly what the old bare `PRIMARY KEY ("key")` could
    // not allow, and what makes the composite key the right fix rather than an unnecessary one.
    expect(() =>
      db
        .prepare(`INSERT INTO diary_meta (user_id, "key", value) VALUES (?, 'pattern_echo_log', ?)`)
        .run(secondUserId, '{}'),
    ).not.toThrow();
    // The same (user_id, key) pair twice is still a collision.
    expect(() =>
      db
        .prepare(`INSERT INTO diary_meta (user_id, "key", value) VALUES (?, 'pattern_echo_log', ?)`)
        .run(DEFAULT_USER_ID, '{}'),
    ).toThrow();
    db.close();
  });
});

describe('migrateDiary — M-1b step 2: topics.name uniqueness rebuild (#46)', () => {
  /**
   * `pre-grouped-vocabulary.db` predates `user_id` entirely, so this fixture exercises the rebuild
   * from the oldest possible starting point: no `user_id` column on `topics` yet, then #134's
   * `ADD COLUMN`, then this ticket's constraint rebuild, all inside the same `migrateDiary` call —
   * exactly the sequence a real, years-old diary goes through in one `npm run migrate-db`.
   */
  it('preserves every topic row and id while changing the constraint to per-user', () => {
    const before = read<{ id: string; name: string; aliases: string }>(
      'SELECT id, name, aliases FROM topics ORDER BY id',
    );
    expect(before.length).toBeGreaterThan(0);

    migrateDiary(target);

    const after = read<{ id: string; user_id: string; name: string; aliases: string }>(
      'SELECT id, user_id, name, aliases FROM topics ORDER BY id',
    );
    expect(after.map(({ id, name, aliases }) => ({ id, name, aliases }))).toEqual(before);
    for (const row of after) expect(row.user_id).toBe(DEFAULT_USER_ID);

    // The constraint itself changed, not just the data — `sqlite_master` is the only place that
    // fact is recorded.
    const db = new Database(target, { readonly: true });
    const schemaSql = (
      db
        .prepare(`SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'topics'`)
        .get() as {
        sql: string;
      }
    ).sql;
    db.close();
    expect(schemaSql).toMatch(/UNIQUE\s*\(\s*user_id\s*,\s*name\s*\)/i);

    expect(() => {
      const opened = openDiary(target);
      assertCompatible(opened);
      opened.close();
    }).not.toThrow();
  });

  it('is idempotent — a second run neither duplicates nor drops a topic', () => {
    migrateDiary(target);
    const once = read<Record<string, unknown>>('SELECT * FROM topics ORDER BY id');

    migrateDiary(target);
    expect(read<Record<string, unknown>>('SELECT * FROM topics ORDER BY id')).toEqual(once);
  });

  it('lets two different users each hold a topic of the same name, once one exists', () => {
    migrateDiary(target);
    const db = new Database(target);
    const secondUserId = '00000000-0000-0000-0000-000000000002';
    db.prepare(`INSERT INTO users (id, email, password_hash, created_at) VALUES (?, ?, ?, ?)`).run(
      secondUserId,
      'second@example.invalid',
      'disabled:no-password-set',
      '2026-01-01 00:00:00.000000',
    );
    const now = '2026-01-01 00:00:00.000000';
    // `sleep` is a topic this fixture's default-user data already holds (verified directly against
    // `pre-grouped-vocabulary.db`) — a real collision under the old bare `UNIQUE (name)`, not a
    // name chosen to avoid the very thing this test means to prove.
    expect(() =>
      db
        .prepare(
          `INSERT INTO topics (id, user_id, name, aliases, first_seen_at, last_seen_at)
           VALUES (?, ?, 'sleep', '[]', ?, ?)`,
        )
        .run('topic-second-user-sleep', secondUserId, now, now),
    ).not.toThrow();
    // The same (user_id, name) pair twice is still a collision.
    expect(() =>
      db
        .prepare(
          `INSERT INTO topics (id, user_id, name, aliases, first_seen_at, last_seen_at)
           VALUES (?, ?, 'sleep', '[]', ?, ?)`,
        )
        .run('topic-second-user-sleep-again', secondUserId, now, now),
    ).toThrow();
    db.close();
  });
});
