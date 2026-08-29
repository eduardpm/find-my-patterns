import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import { loadConfig } from '../config';
import { FEELING_GROUP_SEED, FEELING_SEED, type FeelingSeed } from './feeling-vocabulary';
import { encodeBool, encodeJson } from './codecs';
import { GUIDING_QUESTIONS } from './seed';
import { MIGRATION_STATEMENTS } from './schema';

/**
 * Grows an existing diary to the current reference vocabulary — `npm run migrate-db`.
 *
 * This is the counterpart to `init-db`, and it exists for the same reason that one refuses to
 * touch an existing file: changing a diary is a deliberate act the user performs, never something
 * the server does on startup. The running server still cannot issue DDL (`database.ts` rejects
 * it), so this command opens its own raw connection, exactly as `init-db` does.
 *
 * What it will do:
 *  - create the tables the grouped vocabulary added (`feeling_groups`, `entry_feelings`);
 *  - add the columns it added to `feelings`;
 *  - insert reference rows for groups and feelings that are missing, and refresh the label, group
 *    and order of the ones already there;
 *  - backfill `entry_feelings` from each entry's existing single `feeling_key`.
 *
 * What it will never do: delete a feeling, rename a key, or touch a row in `diary_entries`. A
 * feeling key some entry still points at is left alone even if it has been dropped from the
 * vocabulary, because the alternative is breaking that entry's foreign key.
 */
export interface MigrationReport {
  groupsInserted: number;
  feelingsInserted: number;
  feelingsUpdated: number;
  entryFeelingsBackfilled: number;
  /** Entry-wide intensities moved onto the primary feeling's own row. */
  feelingIntensitiesBackfilled: number;
  guidingQuestionsInserted: number;
  unknownFeelingKeys: string[];
}

function tableColumns(db: Database.Database, table: string): Set<string> {
  return new Set(
    (db.prepare(`SELECT name FROM pragma_table_info(?)`).all(table) as Array<{ name: string }>).map(
      (row) => row.name,
    ),
  );
}

export function migrateDiary(targetPath: string): MigrationReport {
  if (!fs.existsSync(targetPath)) {
    throw new Error(
      `No diary at ${targetPath}. This command only upgrades an existing diary — ` +
        `create one with \`npm run init-db\`.`,
    );
  }

  const db = new Database(targetPath);
  try {
    return db.transaction((): MigrationReport => {
      for (const statement of MIGRATION_STATEMENTS) {
        // An `ADD COLUMN` that names its target is skipped when the column is already there —
        // SQLite has no `IF NOT EXISTS` for columns, and re-running the migration must be a no-op.
        if (statement.table && statement.column) {
          if (tableColumns(db, statement.table).has(statement.column)) continue;
        }
        db.exec(statement.sql);
      }

      const report: MigrationReport = {
        groupsInserted: 0,
        feelingsInserted: 0,
        feelingsUpdated: 0,
        entryFeelingsBackfilled: 0,
        feelingIntensitiesBackfilled: 0,
        guidingQuestionsInserted: 0,
        unknownFeelingKeys: [],
      };

      const insertGroup = db.prepare(
        'INSERT INTO feeling_groups ("key", label, valence, sort_order) VALUES (?, ?, ?, ?)',
      );
      const updateGroup = db.prepare(
        'UPDATE feeling_groups SET label = ?, valence = ?, sort_order = ? WHERE "key" = ?',
      );
      for (const group of FEELING_GROUP_SEED) {
        const exists = db.prepare('SELECT 1 FROM feeling_groups WHERE "key" = ?').get(group.key);
        if (exists) {
          updateGroup.run(group.label, group.valence, group.sortOrder, group.key);
        } else {
          insertGroup.run(group.key, group.label, group.valence, group.sortOrder);
          report.groupsInserted += 1;
        }
      }

      const insertFeeling = db.prepare(
        'INSERT INTO feelings ("key", label, valence, group_key, sort_order) VALUES (?, ?, ?, ?, ?)',
      );
      // Labels, grouping and order are presentation-adjacent reference data that this file owns.
      // Valence is deliberately refreshed too: it is a rule, and a diary disagreeing with the
      // vocabulary about it would make insights point the wrong way.
      const updateFeeling = db.prepare(
        'UPDATE feelings SET label = ?, valence = ?, group_key = ?, sort_order = ? WHERE "key" = ?',
      );
      for (const feeling of FEELING_SEED) {
        const exists = db.prepare('SELECT 1 FROM feelings WHERE "key" = ?').get(feeling.key);
        if (exists) {
          updateFeeling.run(
            feeling.label,
            feeling.valence,
            feeling.groupKey,
            feeling.sortOrder,
            feeling.key,
          );
          report.feelingsUpdated += 1;
        } else {
          insertFeeling.run(
            feeling.key,
            feeling.label,
            feeling.valence,
            feeling.groupKey,
            feeling.sortOrder,
          );
          report.feelingsInserted += 1;
        }
      }

      // A feeling this vocabulary no longer lists but some entry still points at. It keeps its
      // row and its valence; it is only parked in a group so `GET /feelings` can still serve it.
      const known = new Set<string>(FEELING_SEED.map((feeling: FeelingSeed) => feeling.key));
      const orphans = (
        db.prepare('SELECT "key" FROM feelings').all() as Array<{ key: string }>
      ).filter((row) => !known.has(row.key));
      if (orphans.length > 0) {
        report.unknownFeelingKeys = orphans.map((row) => row.key);
        const fallbackGroup = FEELING_GROUP_SEED[FEELING_GROUP_SEED.length - 1].key;
        const park = db.prepare(
          `UPDATE feelings SET group_key = ?, sort_order = 9000 WHERE "key" = ? AND group_key = ''`,
        );
        for (const orphan of orphans) park.run(fallbackGroup, orphan.key);
      }

      // Backfill: an entry that already carried one feeling now carries it as position 0 of a set.
      const backfilled = db
        .prepare(
          `INSERT OR IGNORE INTO entry_feelings (entry_id, feeling_key, position)
           SELECT id, feeling_key, 0 FROM diary_entries WHERE feeling_key IS NOT NULL`,
        )
        .run();
      report.entryFeelingsBackfilled = backfilled.changes;

      // The entry-wide intensity graded whichever feeling happened to be first. Now that intensity
      // lives beside each feeling, that number is moved onto the feeling it was actually about --
      // position 0 -- and nowhere else. The other feelings on the entry stay unrated, because they
      // are: nobody was ever asked about them.
      //
      // Idempotent by the `intensity IS NULL` guard, which is also what makes it safe rather than
      // merely repeatable: a rating the user has since cleared is cleared in both places, so there
      // is nothing here for a later run to resurrect.
      const intensities = db
        .prepare(
          `UPDATE entry_feelings SET intensity =
             (SELECT feeling_intensity FROM diary_entries WHERE diary_entries.id = entry_feelings.entry_id)
           WHERE position = 0 AND intensity IS NULL
             AND (SELECT feeling_intensity FROM diary_entries WHERE diary_entries.id = entry_feelings.entry_id)
                 IS NOT NULL`,
        )
        .run();
      report.feelingIntensitiesBackfilled = intensities.changes;

      // Guiding questions the library has gained since this diary was created — currently the
      // three time-slot prompts (A6). Insert-only and keyed on the question key: an existing
      // question keeps its exact prompt text (A6-02), because entries store a snapshot of the
      // wording they were answered under and rewording one here would make those snapshots lie.
      const insertQuestion = db.prepare(
        `INSERT INTO guiding_questions ("key", category, prompt_text, trigger_keywords, is_mandatory)
         VALUES (?, ?, ?, ?, ?)`,
      );
      for (const [key, category, prompt, keywords, mandatory] of GUIDING_QUESTIONS) {
        const exists = db.prepare('SELECT 1 FROM guiding_questions WHERE "key" = ?').get(key);
        if (exists) continue;
        insertQuestion.run(key, category, prompt, encodeJson(keywords), encodeBool(mandatory));
        report.guidingQuestionsInserted += 1;
      }

      return report;
    })();
  } finally {
    db.close();
  }
}

if (require.main === module) {
  const target = process.argv[2] ?? loadConfig().databasePath;
  try {
    const report = migrateDiary(target);
    console.log(
      `Migrated ${target}\n` +
        `  feeling groups added:   ${report.groupsInserted}\n` +
        `  feelings added:         ${report.feelingsInserted}\n` +
        `  feelings refreshed:     ${report.feelingsUpdated}\n` +
        `  entry feelings backfilled: ${report.entryFeelingsBackfilled}\n` +
        `  feeling intensities moved: ${report.feelingIntensitiesBackfilled}\n` +
        `  guiding questions added: ${report.guidingQuestionsInserted}`,
    );
    if (report.unknownFeelingKeys.length > 0) {
      console.log(`  kept, not in the current vocabulary: ${report.unknownFeelingKeys.join(', ')}`);
    }
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}
