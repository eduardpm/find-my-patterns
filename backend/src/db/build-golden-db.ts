import Database from 'better-sqlite3';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { initDiary } from './init';
import { ALEMBIC_VERSION_STATEMENT } from './schema';

/**
 * Builds `tests/fixtures/golden.db` from scratch — the golden fixture the Playwright `browser`
 * job and most of the backend's own Vitest suite boot against (see `tests/helpers/app.ts`).
 *
 * Why this exists (#83): the fixture used to be a checked-in binary. Two branches that each
 * migrated it produced a binary conflict git could only resolve by picking one side wholesale,
 * silently discarding the other side's schema change — this happened three times in one day. The
 * fix is to never commit the binary at all: generate it, every time, from the same two ingredients
 * everything else in this repo uses to build a diary —
 *
 *  - schema and reference vocabulary come from `initDiary` (`SCHEMA_STATEMENTS`, `seed()`), so the
 *    fixture tracks future vocabulary migrations automatically instead of going stale — including
 *    `guiding_questions.prompt_text`, which now reads current copy the same way a freshly created
 *    diary does (#95: see below);
 *  - the fixture's own content — the 8 entries, 2 topics, 2 materialised patterns, and everything
 *    that hangs off them — comes from `golden-seed.json`, a plain-text, git-mergeable snapshot of
 *    exactly what the binary fixture used to contain. Two branches that each add a row now produce
 *    an ordinary JSON merge conflict, not a binary one silently resolved by picking a side.
 *
 * One thing `initDiary` cannot give us, so this file supplies it directly:
 *
 *  - `alembic_version`, an inert table an earlier migration tool left behind. It is not part of
 *    this backend's schema — `initDiary`/`migrateDiary` never create it, and `assertCompatible`
 *    ignores it outright — but real diaries may carry one, and `compatibility.test.ts` needs a
 *    fixture that does too. `ALEMBIC_VERSION_STATEMENT` (`schema.ts`) is the one statement for it,
 *    kept there so that file stays the only one with DDL text.
 *
 * #95 removed the other thing this file used to supply: `golden-seed.json` carried a
 * `guidingQuestionOverrides` array that force-fed three questions their **pre-#14** wording,
 * because `migrate.ts`'s guiding-question seeding used to be insert-only and could never refresh an
 * existing row — so the only way to reproduce the old committed binary's (stale) copy was to fake
 * it here. Now that `migrateDiary` refreshes `prompt_text` on an existing question the same way it
 * already refreshed `feelings.label` (#95), `initDiary`'s seed alone gives every question current
 * copy, forever, with no override needed. Carrying a general-purpose override mechanism that
 * nothing in this file uses would be dead weight, so it is gone rather than emptied.
 * `tests/contract/entries-write.test.ts`, which used to assert the old wording specifically because
 * of this override, now asserts current copy instead (see its own comment).
 *
 * The fixture-specific rows are inserted through a **raw** `better-sqlite3` connection, the same
 * way `migrate.ts` does — not the guarded connection `openDiary` returns. That is deliberate, not
 * an oversight: `guiding_question_answers` in the fixture cites question keys (`food_drink`,
 * `not_a_real_question`) that are not, and have never been, real `guiding_questions` rows — exactly
 * the "unknown question key" case `tests/fixtures/README.md` documents — and a connection with
 * foreign keys enforced would refuse to write them. `openDiary` turns foreign keys on precisely so
 * cascades work for the running server; a fixture built to exercise the fallback path they guard
 * against cannot be built through it.
 *
 * Every timestamp and id below is copied verbatim from the fixture this replaces, not generated
 * fresh, so the output is byte-stable across rebuilds (`tests/fixtures/README.md`,
 * `tests/e2e/pairing-insights-snapshot.test.ts`'s hardcoded entry/topic ids, and
 * `tests/contract/read-endpoints.test.ts`'s `FIXTURE_MONTH = '2026-07'` all depend on this data
 * not drifting from one build to the next).
 */

interface GoldenSeed {
  alembicVersion: string;
  topics: Array<{
    id: string;
    name: string;
    aliases: string;
    firstSeenAt: string;
    lastSeenAt: string;
  }>;
  diaryEntries: Array<{
    id: string;
    createdAt: string;
    updatedAt: string;
    entryDate: string;
    mode: string;
    rawText: string;
    feelingKey: string | null;
    feelingSource: string;
    version: number;
    feelingIntensity: number | null;
    origin: string;
  }>;
  entryFeelings: Array<{
    entryId: string;
    feelingKey: string;
    position: number;
    intensity: number | null;
  }>;
  entryTopics: Array<{ entryId: string; topicId: string; extractedBy: string | null }>;
  guidingQuestionAnswers: Array<{
    id: string;
    entryId: string;
    questionKey: string;
    questionTextSnapshot: string;
    answerText: string;
    orderIndex: number;
  }>;
  patterns: Array<{
    id: string;
    topicId: string;
    feelingKey: string;
    occurrenceCount: number;
    narrativeText: string;
    suggestionText: string;
    direction: string;
    firstDetectedAt: string;
    lastUpdatedAt: string;
    kind: string;
    lifetimeCount: number;
    status: string;
    lastOccurrenceDate: string | null;
    presentCount: number;
    presentTotal: number;
    absentCount: number;
    absentTotal: number;
    lift: number | null;
    comparisonReason: string | null;
    baseRate: number;
    isStrong: number;
    confounders: string;
    narrationAttempts: number;
    narrationNextAttemptAt: string | null;
  }>;
  patternEntries: Array<{ patternId: string; entryId: string }>;
}

const SEED_PATH = path.resolve(__dirname, '../../tests/fixtures/golden-seed.json');

function loadSeed(): GoldenSeed {
  return JSON.parse(fs.readFileSync(SEED_PATH, 'utf8')) as GoldenSeed;
}

export function buildGoldenDb(targetPath: string): void {
  // A generator builds from scratch every time — `initDiary` refuses to touch a file that exists.
  fs.rmSync(targetPath, { force: true });
  fs.rmSync(`${targetPath}-wal`, { force: true });
  fs.rmSync(`${targetPath}-shm`, { force: true });

  // Schema plus the current reference vocabulary (feeling_groups, feelings, guiding_questions) —
  // exactly what a real diary gets from `npm run init-db`.
  initDiary(targetPath);

  const seed = loadSeed();
  const db = new Database(targetPath);
  // better-sqlite3 turns foreign keys ON by default (unlike the sqlite3 CLI). Off here for the same
  // reason `compatibility.test.ts` turns it off on its own raw connection: `guidingQuestionAnswers`
  // deliberately cites question keys (`food_drink`, `not_a_real_question`) that are not, and have
  // never been, real `guiding_questions` rows — the "unknown question key" case
  // `tests/fixtures/README.md` documents. A connection enforcing foreign keys would refuse to write
  // exactly the row this fixture exists to provide.
  db.pragma('foreign_keys = OFF');
  try {
    db.transaction(() => {
      // The inert leftover table real diaries may carry (see `ALEMBIC_VERSION_STATEMENT`'s doc
      // comment in schema.ts for why this is the one sanctioned place to run it).
      db.exec(ALEMBIC_VERSION_STATEMENT);
      db.prepare('INSERT INTO alembic_version (version_num) VALUES (?)').run(seed.alembicVersion);

      const insertTopic = db.prepare(
        `INSERT INTO topics (id, name, aliases, first_seen_at, last_seen_at)
         VALUES (@id, @name, @aliases, @firstSeenAt, @lastSeenAt)`,
      );
      for (const topic of seed.topics) insertTopic.run(topic);

      const insertEntry = db.prepare(
        `INSERT INTO diary_entries
           (id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source,
            version, feeling_intensity, origin)
         VALUES
           (@id, @createdAt, @updatedAt, @entryDate, @mode, @rawText, @feelingKey, @feelingSource,
            @version, @feelingIntensity, @origin)`,
      );
      for (const entry of seed.diaryEntries) insertEntry.run(entry);

      const insertEntryFeeling = db.prepare(
        `INSERT INTO entry_feelings (entry_id, feeling_key, position, intensity)
         VALUES (@entryId, @feelingKey, @position, @intensity)`,
      );
      for (const row of seed.entryFeelings) insertEntryFeeling.run(row);

      const insertEntryTopic = db.prepare(
        `INSERT INTO entry_topics (entry_id, topic_id, extracted_by)
         VALUES (@entryId, @topicId, @extractedBy)`,
      );
      for (const row of seed.entryTopics) insertEntryTopic.run(row);

      const insertAnswer = db.prepare(
        `INSERT INTO guiding_question_answers
           (id, entry_id, question_key, question_text_snapshot, answer_text, order_index)
         VALUES (@id, @entryId, @questionKey, @questionTextSnapshot, @answerText, @orderIndex)`,
      );
      for (const row of seed.guidingQuestionAnswers) insertAnswer.run(row);

      const insertPattern = db.prepare(
        `INSERT INTO patterns
           (id, topic_id, feeling_key, occurrence_count, narrative_text, suggestion_text, direction,
            first_detected_at, last_updated_at, kind, lifetime_count, status, last_occurrence_date,
            present_count, present_total, absent_count, absent_total, lift, comparison_reason,
            base_rate, is_strong, confounders, narration_attempts, narration_next_attempt_at)
         VALUES
           (@id, @topicId, @feelingKey, @occurrenceCount, @narrativeText, @suggestionText,
            @direction, @firstDetectedAt, @lastUpdatedAt, @kind, @lifetimeCount, @status,
            @lastOccurrenceDate, @presentCount, @presentTotal, @absentCount, @absentTotal, @lift,
            @comparisonReason, @baseRate, @isStrong, @confounders, @narrationAttempts,
            @narrationNextAttemptAt)`,
      );
      for (const row of seed.patterns) insertPattern.run(row);

      const insertPatternEntry = db.prepare(
        `INSERT INTO pattern_entries (pattern_id, entry_id) VALUES (@patternId, @entryId)`,
      );
      for (const row of seed.patternEntries) insertPatternEntry.run(row);
    })();
  } finally {
    db.close();
  }

  // Mirrors `initDiary`'s own posture: diary content is sensitive even in a fixture.
  fs.chmodSync(targetPath, 0o600);
}

if (require.main === module) {
  const target = process.argv[2] ?? path.resolve(__dirname, '../../tests/fixtures/golden.db');
  try {
    buildGoldenDb(target);
    console.log(`Built the golden fixture at ${target}`);
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}
