import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import { ensureDefaultUser } from '../auth/default-user';
import { loadConfig } from '../config';
import { isMixedValence, withinWindow } from '../insights/analysis';
import {
  CONFIRMED_FEELING_SOURCES,
  MIN_OCCURRENCE_THRESHOLD,
  RECENCY_WINDOW_DAYS,
} from '../insights/constants';
import { FEELING_GROUP_SEED, FEELING_SEED, type FeelingSeed } from './feeling-vocabulary';
import { decodeDate, encodeBool, encodeJson, todayLocal, type PlainDate } from './codecs';
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
 *  - insert `guiding_questions` rows the library has gained since the diary was created, and
 *    refresh `prompt_text` on the ones already there (#95 — see the note below the asymmetry this
 *    closes);
 *  - backfill `entry_feelings` from each entry's existing single `feeling_key`.
 *
 * What it will never do: delete a feeling, rename a key, or touch a row in `diary_entries`. A
 * feeling key some entry still points at is left alone even if it has been dropped from the
 * vocabulary, because the alternative is breaking that entry's foreign key.
 *
 * #95: until this change, feelings got their display attributes refreshed on every migration but
 * guiding questions did not — an existing `guiding_questions` row was inserted once and then frozen
 * forever, so a copy edit like #14's (shortening the three mandatory prompts) could never reach a
 * diary that already existed. That asymmetry was the bug, not a safety feature: the thing that
 * makes rewording safe is that `guiding_question_answers.question_text_snapshot` already captures
 * the exact wording an entry was answered under, independent of the current `guiding_questions`
 * row (A6-02 read the insert-only behaviour backwards — see #95). This migration now refreshes
 * `prompt_text` the same way it refreshes `feelings.label`, and leaves `question_text_snapshot`
 * on every past answer untouched, because nothing here writes to that column.
 *
 * #119 (E-1e): also reclassifies stored `pattern_withdrawals` rows a pre-#109 diary mislabelled.
 * `pattern_withdrawals` is written once, at the instant a pattern transitions away
 * (`PatternsService#recordWithdrawal`), and never rewritten by a later recompute — so #109's fix to
 * that classifier only ever applies to a transition that happens *after* the fix landed. Every
 * diary that ran the post-#26, pre-#109 engine already carries `no_longer_confirmed` rows for
 * pairs #26's pairing-exclusion rule actually caused, asserting the false claim #109 was filed to
 * eliminate ("none of them carries a feeling you confirmed") of entries that carry one. See
 * `repairWithdrawalReasons` below for how this is told apart from a genuine `no_longer_confirmed`
 * row, which must and does survive untouched.
 */
export interface MigrationReport {
  groupsInserted: number;
  feelingsInserted: number;
  feelingsUpdated: number;
  entryFeelingsBackfilled: number;
  /** Entry-wide intensities moved onto the primary feeling's own row. */
  feelingIntensitiesBackfilled: number;
  guidingQuestionsInserted: number;
  guidingQuestionsUpdated: number;
  unknownFeelingKeys: string[];
  /** #119: stored `no_longer_confirmed` withdrawals reclassified as `excluded_unpaired`. */
  withdrawalReasonsRepaired: number;
}

function tableColumns(db: Database.Database, table: string): Set<string> {
  return new Set(
    (db.prepare(`SELECT name FROM pragma_table_info(?)`).all(table) as Array<{ name: string }>).map(
      (row) => row.name,
    ),
  );
}

/** What `repairWithdrawalReasons` needs per confirmed-evidence entry — the migration's own,
 *  read-only mirror of `PatternsService#loadEvidenceEntries`'s `LoadedEntry`. */
interface RepairEntry {
  id: string;
  entryDate: PlainDate;
  feelingKeys: string[];
  topicIds: string[];
  confirmedPairs: Set<string>;
}

/**
 * #119 (E-1e): reclassify a stored `no_longer_confirmed` withdrawal as `excluded_unpaired` when
 * the engine's *current* logic says that is what actually happened to it.
 *
 * This is option 1 of the three the issue lists, in preference order — true reclassification,
 * not a vaguer rewrite (option 2) or deletion (option 3). It is reachable because everything the
 * determination needs is still on disk: #26's pairing-exclusion rule and #109's
 * `excludedFromThreshold` test are both pure functions of the diary's current entries, topics and
 * confirmed pairings, none of which this migration touches. Re-deriving them here — rather than
 * booting `PatternsService` — keeps this file's one deliberate constraint intact: a migration
 * opens its own raw connection and never depends on the Nest application (`migrateDiary`'s own doc
 * comment). The cost is duplicating a slice of `buildCandidates`; the alternative was standing up
 * dependency injection inside a CLI migration, which is worse.
 *
 * The determination, mirroring `PatternsService#recordWithdrawal`'s own branch exactly:
 * a stored `no_longer_confirmed` row is exclusion-caused, and only then, when its pair is
 * `kind === 'forward'` (E-1d: rule 2 never touches an inverse pattern's absent side, so an inverse
 * row can never be exclusion-caused — see `buildCandidates`'s own comment on `excludedFromThreshold`)
 * and its `(topic_id, feeling_key)` key is in `excludedFromThreshold` — evidence that would have
 * cleared `MIN_OCCURRENCE_THRESHOLD` were it not for #26's exclusion, recomputed fresh from today's
 * diary. A row whose pair fails that test is left untouched: the genuine case (an entry's feeling
 * really was un-confirmed, e.g. edited back to `suggested`) never touches this table at all, since
 * `loadEvidenceEntries`/its mirror below drop such an entry from `entries` entirely rather than
 * merely from `confirmedPairs`, so its raw lifetime count for the pair never reaches
 * `MIN_OCCURRENCE_THRESHOLD` and the pair never enters `excludedFromThreshold`.
 *
 * Idempotent by construction: once a row's `reason` becomes `excluded_unpaired`, the `WHERE
 * reason = 'no_longer_confirmed'` guard below no longer selects it, so a second run touches
 * nothing. `withdrawn_at` is never written here, which is what keeps `is_new` — `listWithdrawals`
 * compares it against `withdrawals_acknowledged_at` — exactly as the maintainer already found it;
 * repairing a stale sentence must not re-flag 33 old notices as new ones.
 */
function repairWithdrawalReasons(db: Database.Database, today: PlainDate): number {
  const candidates = db
    .prepare(
      `SELECT id, topic_id, feeling_key FROM pattern_withdrawals
       WHERE reason = 'no_longer_confirmed' AND kind = 'forward'`,
    )
    .all() as Array<{ id: string; topic_id: string; feeling_key: string }>;
  if (candidates.length === 0) return 0;

  // --- Reconstruct buildCandidates' exclusion inputs from the diary's current state -------------
  const sourcePlaceholders = CONFIRMED_FEELING_SOURCES.map(() => '?').join(', ');
  const byEntry = new Map<string, RepairEntry>();
  for (const row of db
    .prepare(
      `SELECT e.id, e.entry_date, ef.feeling_key
       FROM diary_entries e JOIN entry_feelings ef ON ef.entry_id = e.id
       WHERE e.feeling_source IN (${sourcePlaceholders})`,
    )
    .all(...CONFIRMED_FEELING_SOURCES) as Array<{
    id: string;
    entry_date: string;
    feeling_key: string;
  }>) {
    let entry = byEntry.get(row.id);
    if (!entry) {
      entry = {
        id: row.id,
        entryDate: decodeDate(row.entry_date),
        feelingKeys: [],
        topicIds: [],
        confirmedPairs: new Set(),
      };
      byEntry.set(row.id, entry);
    }
    entry.feelingKeys.push(row.feeling_key);
  }
  // Nothing currently carries a confirmed feeling — every stored row is either genuinely
  // `no_longer_confirmed` (correct as-is) or the topic underneath it is gone entirely. Either way
  // there is no reliable determination to make, so this bails before running the loops below on
  // an empty diary.
  if (byEntry.size === 0) return 0;

  for (const row of db.prepare('SELECT entry_id, topic_id FROM entry_topics').all() as Array<{
    entry_id: string;
    topic_id: string;
  }>) {
    byEntry.get(row.entry_id)?.topicIds.push(row.topic_id);
  }
  for (const row of db
    .prepare(
      `SELECT entry_id, topic_id, feeling_key FROM entry_topic_feelings
       WHERE source IN (${sourcePlaceholders})`,
    )
    .all(...CONFIRMED_FEELING_SOURCES) as Array<{
    entry_id: string;
    topic_id: string;
    feeling_key: string;
  }>) {
    byEntry.get(row.entry_id)?.confirmedPairs.add(`${row.topic_id} ${row.feeling_key}`);
  }

  const valences = new Map(
    (
      db.prepare('SELECT "key", valence FROM feelings').all() as Array<{
        key: string;
        valence: string;
      }>
    ).map((row) => [row.key, row.valence]),
  );
  const entries = [...byEntry.values()];

  // E-1b rule 1/4, unchanged from `buildCandidates`: whether an entry's own feelings span both
  // valence signs, which is what makes it mixed-valence and subject to the pairing rule at all.
  const isMixedByEntry = new Map<string, boolean>(
    entries.map((entry) => [
      entry.id,
      isMixedValence(entry.feelingKeys, (key) => valences.get(key)),
    ]),
  );
  const isPairExcluded = (entry: RepairEntry, topicId: string, feelingKey: string): boolean =>
    (isMixedByEntry.get(entry.id) ?? false) &&
    !entry.confirmedPairs.has(`${topicId} ${feelingKey}`);

  // rawLifetimeCounts: every confirmed pair a current entry forms, exclusion or not.
  // lifetimeCounts: the same tally with rule 2's exclusion applied — `excludedFromThreshold`'s gap.
  const rawLifetimeCounts = new Map<string, number>();
  const lifetimeCounts = new Map<string, number>();
  for (const entry of entries) {
    for (const topicId of entry.topicIds) {
      for (const feelingKey of entry.feelingKeys) {
        const key = `${topicId} ${feelingKey}`;
        rawLifetimeCounts.set(key, (rawLifetimeCounts.get(key) ?? 0) + 1);
        if (!isPairExcluded(entry, topicId, feelingKey)) {
          lifetimeCounts.set(key, (lifetimeCounts.get(key) ?? 0) + 1);
        }
      }
    }
  }
  const excludedFromThreshold = new Set<string>();
  for (const [key, raw] of rawLifetimeCounts) {
    if (raw < MIN_OCCURRENCE_THRESHOLD) continue;
    if ((lifetimeCounts.get(key) ?? 0) < MIN_OCCURRENCE_THRESHOLD) excludedFromThreshold.add(key);
  }

  // The diary-wide `excluded_unpaired` figure the repaired sentence cites — the same definition
  // `buildCandidates` uses for `InsightsOut.excluded_unpaired`, recomputed fresh against today's
  // window rather than preserved from the moment of the original (mislabelled) withdrawal, which
  // this migration has no record of. It is a true statement about the diary today, which is what a
  // vague-but-honest fallback would have to settle for everywhere; reclassification gets to state
  // it exactly because the diary still holds the evidence.
  const inWindow = entries.filter((entry) =>
    withinWindow(entry.entryDate, today, RECENCY_WINDOW_DAYS),
  );
  const excludedUnpairedNow = inWindow.filter(
    (entry) =>
      (isMixedByEntry.get(entry.id) ?? false) &&
      entry.confirmedPairs.size === 0 &&
      entry.topicIds.length > 0,
  ).length;

  const topicNames = new Map(
    (db.prepare('SELECT id, name FROM topics').all() as Array<{ id: string; name: string }>).map(
      (row) => [row.id, row.name],
    ),
  );

  const update = db.prepare(
    'UPDATE pattern_withdrawals SET reason = ?, detail_text = ? WHERE id = ?',
  );
  const entriesWord = (count: number): string => `${count} ${count === 1 ? 'entry' : 'entries'}`;
  let repaired = 0;

  for (const row of candidates) {
    const pairKey = `${row.topic_id} ${row.feeling_key}`;
    if (!excludedFromThreshold.has(pairKey)) continue;
    // The topic must still exist to state its current name; if it was merged away since the
    // withdrawal, `rawLifetimeCounts` for its old id is already 0 (no current entry can reference
    // a deleted topic_id — `entry_topics` cascades on the merge), so it can never have reached
    // `excludedFromThreshold` in the first place. This check is therefore unreachable in practice,
    // and kept only as the same defensive guard `recordWithdrawal` itself applies before naming a
    // topic.
    const topicName = topicNames.get(row.topic_id);
    if (topicName === undefined) continue;

    const label = `${topicName} → ${row.feeling_key}`;
    const detail =
      `${label} was withdrawn: its entries carry a feeling you confirmed, but never a confirmed ` +
      `pairing between the two — ${entriesWord(excludedUnpairedNow)} diary-wide are excluded from ` +
      `counting until they are paired.`;
    update.run('excluded_unpaired', detail, row.id);
    repaired += 1;
  }

  return repaired;
}

export function migrateDiary(targetPath: string): MigrationReport {
  if (!fs.existsSync(targetPath)) {
    throw new Error(
      `No diary at ${targetPath}. This command only upgrades an existing diary — ` +
        `create one with \`npm run init-db\`.`,
    );
  }

  const db = new Database(targetPath);
  // better-sqlite3 defaults a fresh raw connection's `foreign_keys` pragma to **on** (unlike the
  // sqlite3 CLI) — confirmed against this project's actual dependency version, not assumed. Off
  // here for two reasons, both from M-1b (#134): SQLite refuses `ALTER TABLE ... ADD COLUMN` for a
  // column that carries both a `REFERENCES` clause and a non-NULL default while foreign keys are
  // enforced ("Cannot add a REFERENCES column with non-NULL default value"), which is exactly the
  // shape every new `user_id` column below has; and the running server's own connection
  // (`database.ts`) already runs permanently with `foreign_keys = OFF`, for the same reason it
  // gives — an existing diary may already disagree with a declared foreign key (`sessions`'s guard
  // in `openDiary`'s doc comment), and enforcing one here would turn reading a real diary into an
  // error. This does not relax anything a real diary depended on; it matches the posture the
  // fixture builder (`build-golden-db.ts`) and the live connection both already have.
  db.pragma('foreign_keys = OFF');
  try {
    return db.transaction((): MigrationReport => {
      for (const statement of MIGRATION_STATEMENTS) {
        // An `ADD COLUMN` that names its target is skipped when the column is already there —
        // SQLite has no `IF NOT EXISTS` for columns, and re-running the migration must be a no-op.
        if (statement.table && statement.column) {
          if (tableColumns(db, statement.table).has(statement.column)) continue;
        } else if (statement.skipIf?.(db)) {
          // A guard `table`/`column` cannot express — see `MigrationStatement.skipIf`'s doc
          // comment (`schema.ts`) and `topicsAlreadyRebuilt` for the one statement group that
          // needs this today.
          continue;
        }
        db.exec(statement.sql);
      }

      // M-1a (#45): the `users` table above was just created (or already existed, if this is a
      // re-run). Either way, the default user must exist by the time this function returns — the
      // acceptance criteria require it immediately, not only after the server next boots and runs
      // `seed()` (`./seed.ts`, which calls the same function for a fresh diary created via
      // `init-db`).
      ensureDefaultUser(db);

      const report: MigrationReport = {
        groupsInserted: 0,
        feelingsInserted: 0,
        feelingsUpdated: 0,
        entryFeelingsBackfilled: 0,
        feelingIntensitiesBackfilled: 0,
        guidingQuestionsInserted: 0,
        guidingQuestionsUpdated: 0,
        unknownFeelingKeys: [],
        withdrawalReasonsRepaired: 0,
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

      // Guiding questions: insert the ones the library has gained since this diary was created
      // (currently the three time-slot prompts, A6), and refresh `prompt_text` on the ones already
      // there (#95) so a copy change like #14's reaches every diary, not just freshly created ones.
      //
      // `prompt_text` is the only column refreshed here. `key` is identity by definition (it is
      // the primary key and the foreign key `guiding_question_answers.question_key` points at).
      // `category` and `trigger_keywords` are left alone too, deliberately: `category` groups
      // questions for the client (e.g. driving which time-slot prompt is offered), and
      // `trigger_keywords` decides *whether a question is offered at all* for a given entry
      // (`question-yield` reads it to match against entry text) — both are behaviour, not
      // presentation, so silently changing them under an existing key would change what a diary
      // does, not just what it says. `is_mandatory` is left alone for the same reason: it decides
      // whether the client can skip the question, which is behaviour a copy refresh has no
      // business touching. Only `prompt_text` is pure display text with no behavioural reading
      // anywhere in the codebase, which is what makes it — and only it — safe to refresh here.
      //
      // This cannot corrupt history: `guiding_question_answers.question_text_snapshot` already
      // captures the exact wording an entry was answered under, independent of this table, so an
      // update here changes only what a *future* entry sees.
      const insertQuestion = db.prepare(
        `INSERT INTO guiding_questions ("key", category, prompt_text, trigger_keywords, is_mandatory)
         VALUES (?, ?, ?, ?, ?)`,
      );
      const updateQuestion = db.prepare(
        'UPDATE guiding_questions SET prompt_text = ? WHERE "key" = ?',
      );
      for (const [key, category, prompt, keywords, mandatory] of GUIDING_QUESTIONS) {
        const exists = db.prepare('SELECT 1 FROM guiding_questions WHERE "key" = ?').get(key);
        if (exists) {
          updateQuestion.run(prompt, key);
          report.guidingQuestionsUpdated += 1;
        } else {
          insertQuestion.run(key, category, prompt, encodeJson(keywords), encodeBool(mandatory));
          report.guidingQuestionsInserted += 1;
        }
      }

      // #119: repair stored withdrawal notices #109's fix couldn't reach — see
      // `repairWithdrawalReasons`'s own doc comment. `todayLocal()` is read once, here, exactly as
      // `PatternsService#recomputePatterns` reads it once per recompute (C-02: two computations of
      // "today" mid-migration could disagree about which entries are in the 30-day window).
      report.withdrawalReasonsRepaired = repairWithdrawalReasons(db, todayLocal());

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
        `  guiding questions added:   ${report.guidingQuestionsInserted}\n` +
        `  guiding questions refreshed: ${report.guidingQuestionsUpdated}\n` +
        `  withdrawal reasons repaired: ${report.withdrawalReasonsRepaired}`,
    );
    if (report.unknownFeelingKeys.length > 0) {
      console.log(`  kept, not in the current vocabulary: ${report.unknownFeelingKeys.join(', ')}`);
    }
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}
