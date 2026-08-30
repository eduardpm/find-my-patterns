import type Database from 'better-sqlite3';
import { DEFAULT_USER_ID } from '../auth/default-user';

/**
 * The diary schema.
 *
 * **This is the only file in the project permitted to contain DDL**, and it is used by exactly one
 * entry point: `npm run init-db`. The running server never executes any of it — the connection in
 * `database.ts` rejects DDL outright, and the lint rule that enforces that is disabled here
 * deliberately rather than by accident.
 *
 * Creating a diary is an explicit act the user performs once. It is not something a server does on
 * startup, because "the file wasn't there so I made a new one" is indistinguishable from data loss.
 */

// --- Multi-tenant scoping, step 1 (M-1b, #134) ----------------------------------------------------
// Every user-data table below carries `user_id VARCHAR(36) NOT NULL DEFAULT '<DEFAULT_USER_ID>'`.
// The default is deliberate, not a placeholder to remove later: #46 (M-1b step 2) is what threads a
// real, authenticated user id into every INSERT this codebase makes — until that lands, every row
// any service writes is still the one pre-multi-tenant user's data, so defaulting a column nothing
// yet populates to `DEFAULT_USER_ID` is what keeps this change behaviour-preserving. The column is
// plain `NOT NULL DEFAULT ...`, not `NOT NULL` bare, for exactly that reason: every existing
// `INSERT` statement in `src/` still omits this column, and a bare `NOT NULL` would make every one
// of them start failing the moment a fresh diary existed.
//
// `FOREIGN KEY(user_id) REFERENCES users (id)` is declared (matching `sessions`/`entitlements`
// below) but never `ON DELETE CASCADE`: deleting a user is not a feature this codebase has, so
// deciding what happens to their diary content on deletion is a decision for whichever ticket adds
// that feature, not one to make speculatively here by copying a clause that happens to be nearby.
// Declaring the FK at all is enforcement-optional in the same sense every other FK in this schema
// already is — `database.ts` runs the live connection with `foreign_keys = OFF` — so it documents
// the relationship for a reader without depending on SQLite to enforce it.
//
// Six tables in `compatibility.ts`'s `REQUIRED` map are deliberately **not** touched: `feelings`,
// `feeling_groups` and `guiding_questions` are shared reference vocabulary, not user data — seeded
// once by `initDiary`/`migrateDiary` and read the same way regardless of who is asking. `users`,
// `sessions` and `entitlements` already carry the ownership this ticket is adding everywhere else
// (M-1a, #45; M-2, #47). `alembic_version` is inert (`tests/fixtures/README.md`) and outside
// `REQUIRED` entirely.
//
// Every other table here is user data, including five junction/child tables whose row is only
// *transitively* owned through a parent (`entry_feelings`, `entry_topics`, `pattern_entries`,
// `entry_topic_feelings`, `guiding_question_answers` — each already carries the id of a diary_entries
// row that has its own `user_id`). Denormalising `user_id` onto them anyway is a deliberate choice,
// not an oversight: #46 needs a `WHERE user_id = ?` (and a matching index) that works on the table
// being queried, not one that depends on a join back to `diary_entries` being written correctly on
// every call site that touches it. A missing or wrong join is exactly the kind of scoping bug this
// split exists to make less likely; a column that is simply present is not.
//
// `diary_meta` is the one case worth arguing rather than asserting: its two keys —
// `pattern_echo_log` (`insights/echo.service.ts`) and `withdrawals_acknowledged_at`
// (`insights/patterns.service.ts`) — are both about what *this user* has already seen, not
// anything the server tracks about itself, so it is user data and belongs in this list. Its old
// primary key was the bare `"key"` string, which only worked because there was exactly one user;
// once two users can each have their own `pattern_echo_log` row, `"key"` alone can no longer tell
// them apart, so the primary key becomes the composite `(user_id, "key")` below.
//
// --- Two global uniqueness constraints, one fixed here, one deliberately not (M-1b step 2, #46) --
// #134 flagged both `topics.name`'s bare `UNIQUE` and `csv_imports.content_hash`'s bare primary key
// as real multi-tenant defects and left them for this ticket to decide. They are not the same
// defect in practice, and #46 treats them differently:
//
//  - `topics.name` is fixed here, below, to `UNIQUE (user_id, name)`. Every service that reads or
//    writes `topics` was already scoping its queries by `user_id` as part of this ticket's own
//    work (`TopicsService`) — but the bare `UNIQUE (name)` constraint meant two ordinary accounts
//    both mentioning "coffee" (an entirely routine occurrence, not an edge case) would collide the
//    moment the second one's `INSERT` ran, turning `GET /insights` — the single most-called
//    endpoint, since it recomputes on every read — into a 500 for that account. That is not a rare
//    coincidence to defer; it is the ordinary case for two unrelated diaries. Migrated via a table
//    rebuild (`MIGRATION_STATEMENTS` below), the same technique `diary_meta`'s primary-key change
//    already uses, since SQLite has no `ALTER TABLE ... ADD CONSTRAINT`.
//  - `csv_imports.content_hash` stays a bare, global primary key, deliberately. Its collision only
//    fires when two different accounts import byte-identical files — genuinely rare, unlike two
//    people both writing about coffee — and `DaylioImportService`/`DaylioImportController`
//    (`daylio-import.service.ts`'s `DaylioContentHashCollisionError` doc comment) already turn that
//    rare case into an honest 409 instead of a silent no-op or an unhandled 500. Rebuilding this
//    table's primary key to `(user_id, content_hash)` is real work — it changes what "idempotent"
//    means for every future import, not just an ownership filter — and belongs in its own
//    reviewable, migration-tested follow-up (named in this ticket's PR description) rather than
//    folded into an already-large one under time pressure.

export const SCHEMA_STATEMENTS: string[] = [
  `CREATE TABLE feeling_groups (
     "key" VARCHAR(32) NOT NULL,
     label VARCHAR(64) NOT NULL,
     valence VARCHAR(16) NOT NULL,
     sort_order INTEGER NOT NULL,
     PRIMARY KEY ("key")
   )`,

  `CREATE TABLE feelings (
     "key" VARCHAR(32) NOT NULL,
     label VARCHAR(64) NOT NULL,
     valence VARCHAR(16) NOT NULL,
     group_key VARCHAR(32) NOT NULL,
     sort_order INTEGER NOT NULL,
     PRIMARY KEY ("key"),
     FOREIGN KEY(group_key) REFERENCES feeling_groups ("key")
   )`,

  `CREATE TABLE guiding_questions (
     "key" VARCHAR(64) NOT NULL,
     category VARCHAR(32) NOT NULL,
     prompt_text VARCHAR(256) NOT NULL,
     trigger_keywords JSON NOT NULL,
     is_mandatory BOOLEAN NOT NULL,
     PRIMARY KEY ("key")
   )`,

  `CREATE TABLE topics (
     id VARCHAR(36) NOT NULL,
     user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
     name VARCHAR(128) NOT NULL,
     aliases JSON NOT NULL,
     first_seen_at DATETIME NOT NULL,
     last_seen_at DATETIME NOT NULL,
     PRIMARY KEY (id),
     UNIQUE (user_id, name),
     FOREIGN KEY(user_id) REFERENCES users (id)
   )`,

  `CREATE TABLE diary_entries (
     id VARCHAR(36) NOT NULL,
     user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
     created_at DATETIME NOT NULL,
     updated_at DATETIME NOT NULL,
     entry_date DATE NOT NULL,
     mode VARCHAR(16) NOT NULL,
     raw_text TEXT NOT NULL,
     feeling_key VARCHAR(32),
     feeling_source VARCHAR(16) NOT NULL,
     version INTEGER DEFAULT '1' NOT NULL,
     feeling_intensity INTEGER,
     -- Provenance marker (L-1b, #35): 'app' for every entry written through the normal compose
     -- flow, 'daylio_import' for a row the Daylio importer wrote. Defaults to 'app' so every
     -- entry a diary already holds is correctly labelled the instant this column appears — see
     -- MIGRATION_STATEMENTS below.
     origin VARCHAR(16) NOT NULL DEFAULT 'app',
     PRIMARY KEY (id),
     FOREIGN KEY(feeling_key) REFERENCES feelings ("key"),
     FOREIGN KEY(user_id) REFERENCES users (id)
   )`,

  `CREATE TABLE entry_feelings (
     entry_id VARCHAR(36) NOT NULL,
     user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
     feeling_key VARCHAR(32) NOT NULL,
     position INTEGER NOT NULL,
     intensity INTEGER,
     PRIMARY KEY (entry_id, feeling_key),
     FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
     FOREIGN KEY(feeling_key) REFERENCES feelings ("key"),
     FOREIGN KEY(user_id) REFERENCES users (id)
   )`,

  `CREATE TABLE guiding_question_answers (
     id VARCHAR(36) NOT NULL,
     user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
     entry_id VARCHAR(36) NOT NULL,
     question_key VARCHAR(64) NOT NULL,
     question_text_snapshot VARCHAR(256) NOT NULL,
     answer_text VARCHAR(1024) NOT NULL,
     order_index INTEGER NOT NULL,
     PRIMARY KEY (id),
     FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
     FOREIGN KEY(question_key) REFERENCES guiding_questions ("key"),
     FOREIGN KEY(user_id) REFERENCES users (id)
   )`,

  `CREATE TABLE entry_topics (
     entry_id VARCHAR(36) NOT NULL,
     topic_id VARCHAR(36) NOT NULL,
     user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
     extracted_by VARCHAR(16),
     PRIMARY KEY (entry_id, topic_id),
     FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
     FOREIGN KEY(topic_id) REFERENCES topics (id) ON DELETE CASCADE,
     FOREIGN KEY(user_id) REFERENCES users (id)
   )`,

  `CREATE TABLE patterns (
     id VARCHAR(36) NOT NULL,
     user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
     topic_id VARCHAR(36) NOT NULL,
     feeling_key VARCHAR(32) NOT NULL,
     occurrence_count INTEGER NOT NULL,
     narrative_text VARCHAR(512) NOT NULL,
     suggestion_text VARCHAR(512) NOT NULL,
     direction VARCHAR(16) NOT NULL,
     first_detected_at DATETIME NOT NULL,
     last_updated_at DATETIME NOT NULL,
     kind VARCHAR(16) NOT NULL DEFAULT 'forward',
     lifetime_count INTEGER NOT NULL DEFAULT 0,
     status VARCHAR(16) NOT NULL DEFAULT 'active',
     last_occurrence_date DATE,
     present_count INTEGER NOT NULL DEFAULT 0,
     present_total INTEGER NOT NULL DEFAULT 0,
     absent_count INTEGER NOT NULL DEFAULT 0,
     absent_total INTEGER NOT NULL DEFAULT 0,
     lift REAL,
     comparison_reason VARCHAR(32),
     base_rate REAL NOT NULL DEFAULT 0,
     is_strong BOOLEAN NOT NULL DEFAULT 0,
     confounders JSON NOT NULL DEFAULT '[]',
     narration_attempts INTEGER NOT NULL DEFAULT 0,
     narration_next_attempt_at DATETIME,
     PRIMARY KEY (id),
     FOREIGN KEY(feeling_key) REFERENCES feelings ("key"),
     FOREIGN KEY(topic_id) REFERENCES topics (id),
     FOREIGN KEY(user_id) REFERENCES users (id)
   )`,

  `CREATE TABLE pattern_entries (
     pattern_id VARCHAR(36) NOT NULL,
     entry_id VARCHAR(36) NOT NULL,
     user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
     PRIMARY KEY (pattern_id, entry_id),
     FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
     FOREIGN KEY(pattern_id) REFERENCES patterns (id) ON DELETE CASCADE,
     FOREIGN KEY(user_id) REFERENCES users (id)
   )`,

  `CREATE TABLE inference_jobs (
     id VARCHAR(36) NOT NULL,
     user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
     kind VARCHAR(32) NOT NULL,
     entry_id VARCHAR(36) NOT NULL,
     status VARCHAR(16) NOT NULL,
     result_json JSON,
     error_text TEXT,
     attempts INTEGER NOT NULL,
     created_at DATETIME NOT NULL,
     started_at DATETIME,
     completed_at DATETIME,
     PRIMARY KEY (id),
     FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
     FOREIGN KEY(user_id) REFERENCES users (id)
   )`,

  `CREATE TABLE pattern_withdrawals (
     id VARCHAR(36) NOT NULL,
     user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
     pattern_key VARCHAR(160) NOT NULL,
     topic_id VARCHAR(36) NOT NULL,
     topic_name VARCHAR(128) NOT NULL,
     feeling_key VARCHAR(32) NOT NULL,
     kind VARCHAR(16) NOT NULL,
     previous_count INTEGER NOT NULL,
     new_count INTEGER NOT NULL,
     reason VARCHAR(32) NOT NULL,
     detail_text VARCHAR(512) NOT NULL,
     withdrawn_at DATETIME NOT NULL,
     superseded_at DATETIME,
     PRIMARY KEY (id),
     FOREIGN KEY(user_id) REFERENCES users (id)
   )`,

  // `PRIMARY KEY (user_id, "key")`, not the bare `("key")` this table shipped with — see the M-1b
  // note at the top of this file for why a per-user key/value fact needs the owner in its key.
  `CREATE TABLE diary_meta (
     user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
     "key" VARCHAR(64) NOT NULL,
     value TEXT NOT NULL,
     PRIMARY KEY (user_id, "key"),
     FOREIGN KEY(user_id) REFERENCES users (id)
   )`,

  // --- N-of-1 experiments (R-3a) ------------------------------------------------------------
  // `pattern_topic` is the topic *name*, not `topics.id` — a topic can be merged into another
  // (A4-05), and an experiment must go on naming the topic it was actually started on even if
  // its row later merges away. `pattern_feeling` does carry a foreign key: the feeling vocabulary
  // is curated and stable, so a feeling key never goes stale the way a topic id can.
  `CREATE TABLE experiments (
     id VARCHAR(36) NOT NULL,
     user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
     pattern_topic VARCHAR(128) NOT NULL,
     pattern_feeling VARCHAR(32) NOT NULL,
     hypothesis_kind VARCHAR(16) NOT NULL,
     start_date DATE NOT NULL,
     end_date DATE NOT NULL,
     status VARCHAR(16) NOT NULL DEFAULT 'active',
     created_at DATETIME NOT NULL,
     PRIMARY KEY (id),
     FOREIGN KEY(pattern_feeling) REFERENCES feelings ("key"),
     FOREIGN KEY(user_id) REFERENCES users (id)
   )`,

  // --- Mixed-valence pairing (E-1a) -----------------------------------------------------------
  // Topics and feelings both attach to the whole entry, which is wrong the moment an entry mixes
  // valence: "missed my workout, disappointing — but a lovely call with my family" would otherwise
  // feed *four* topic×feeling counts into the pattern engine, two of them false
  // (workout×grateful, family×disappointed). This table is the sub-entry link the LLM proposes and
  // the user confirms or overrides, carrying the same `suggested / confirmed / overridden` source
  // semantics `diary_entries.feeling_source` already carries — only a confirmed or overridden row
  // may ever count as evidence (that counting rule is E-1b, not here). The primary key is the
  // triple rather than a surrogate id: a (topic, feeling) pairing on one entry is either present or
  // it is not, so there is nothing a second row for the same triple could mean.
  `CREATE TABLE entry_topic_feelings (
     entry_id VARCHAR(36) NOT NULL,
     topic_id VARCHAR(36) NOT NULL,
     feeling_key VARCHAR(32) NOT NULL,
     user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
     source VARCHAR(16) NOT NULL,
     PRIMARY KEY (entry_id, topic_id, feeling_key),
     FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
     FOREIGN KEY(topic_id) REFERENCES topics (id) ON DELETE CASCADE,
     FOREIGN KEY(feeling_key) REFERENCES feelings ("key"),
     FOREIGN KEY(user_id) REFERENCES users (id)
   )`,

  // --- Daylio CSV import idempotency (L-1b, #35) ------------------------------------------------
  // One row per committed file. `content_hash` (sha256 of the raw upload) is what makes a commit
  // idempotent: re-posting the exact same export cannot double-import, because the second commit
  // finds its hash already here and writes nothing. `report_json` is the dry-run report that was
  // accepted, kept for `GET`-free auditability — "what did this import actually do" never requires
  // re-parsing the original file.
  //
  // `user_id` is added (M-1b, #134) but `content_hash` stays the bare primary key: see this file's
  // top-of-file note (M-1b step 2, #46) on why that per-user uniqueness fix is deliberately left to
  // a follow-up ticket rather than this one.
  `CREATE TABLE csv_imports (
     content_hash VARCHAR(64) NOT NULL,
     user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
     source VARCHAR(16) NOT NULL,
     imported_at DATETIME NOT NULL,
     entry_count INTEGER NOT NULL,
     report_json JSON NOT NULL,
     PRIMARY KEY (content_hash),
     FOREIGN KEY(user_id) REFERENCES users (id)
   )`,

  // --- Multi-tenant identity (M-1a, #45) ----------------------------------------------------------
  // The first step of the multi-tenant rewrite: accounts and bearer-token sessions. Every other
  // table stays single-tenant until M-1b adds `user_id` scoping — this migration is identity and
  // plumbing only. `id` is VARCHAR(36) like every other id in this schema (a UUID), not an
  // autoincrementing integer, so M-1b can give nearly every table a `user_id VARCHAR(36)` foreign
  // key of the same type everywhere; the fixed pre-multi-tenant "default user" both tickets need to
  // name is `DEFAULT_USER_ID` in `src/auth/default-user.ts`, not literally row 1.
  `CREATE TABLE users (
     id VARCHAR(36) NOT NULL,
     email VARCHAR(256) NOT NULL,
     password_hash VARCHAR(256) NOT NULL,
     created_at DATETIME NOT NULL,
     PRIMARY KEY (id),
     UNIQUE (email)
   )`,

  // Opaque, server-stored bearer-token sessions (`src/auth/tokens.ts` documents the choice over a
  // JWT). Only `token_hash` — sha256 of the raw token — is ever stored, mirroring why
  // `users.password_hash` holds a hash rather than a password: a leaked row must not itself be a
  // usable credential.
  `CREATE TABLE sessions (
     token_hash VARCHAR(64) NOT NULL,
     user_id VARCHAR(36) NOT NULL,
     created_at DATETIME NOT NULL,
     expires_at DATETIME NOT NULL,
     PRIMARY KEY (token_hash),
     FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
   )`,

  // --- Server-side entitlements (M-2, #47) --------------------------------------------------------
  // `daylio-competitive-analysis.md` §11.2 rule 4: a client-side paywall over an open API is
  // decorative, so the backend — not the Android client — is the source of truth for who paid.
  // `user_id` is the primary key rather than a surrogate `id`: exactly one entitlement state per
  // user is the whole model, so there is nothing a second row for the same user could ever mean.
  //
  // No row is inserted for a user who has never verified a purchase, on either fresh init or
  // migration — unlike `users`/`sessions`, "everyone defaults to free" (the issue's task 1) is
  // expressed as *absence*, not as a seeded `'free'` row for every account. `EntitlementsService`
  // (`../billing/entitlements.service.ts`) treats a missing row and an explicit `tier = 'free'` row
  // identically, which is what makes that free choice for new/never-purchased accounts, including
  // the M-1a default user, cost nothing to keep correct as `users` grows.
  //
  // `expires_at` NULL means a lifetime entitlement — it must never expire, so `EntitlementsService`
  // and the daily sweep both treat NULL as "not a candidate for expiry" rather than "expires
  // immediately", the trap a naive `expires_at <= now` comparison would fall into if NULL sorted as
  // the smallest possible value.
  `CREATE TABLE entitlements (
     user_id VARCHAR(36) NOT NULL,
     tier VARCHAR(16) NOT NULL DEFAULT 'free',
     source VARCHAR(16) NOT NULL DEFAULT 'manual',
     expires_at DATETIME,
     updated_at DATETIME NOT NULL,
     PRIMARY KEY (user_id),
     FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
   )`,

  // --- The first indexes in this schema (M-1b, #134) ----------------------------------------------
  // `schema.ts` carried zero indexes before this — every read was a full-table scan, tolerable at
  // one user's worth of data. Each index below is named for a query that already exists in `src/`
  // today; #46 turns that query's `WHERE`/`ORDER BY` into a `user_id`-scoped one, and the leading
  // `user_id` column is what makes that future filter an index seek rather than the scan it is now.
  // None of these change any query's result — SQLite indexes are a plan choice, never a filter —
  // which is what keeps adding them inside this behaviour-preserving ticket.
  //
  //  - `diary_entries(user_id, entry_date)`: `entries.repository.ts`'s
  //    `WHERE entry_date >= ? AND entry_date <= ?` (month range) and `WHERE entry_date = ?`
  //    (duplicate-entry check) both filter on exactly this pair once `user_id` joins them.
  //  - `patterns(user_id, last_updated_at)`: `worker.ts`'s `narrateNextPattern` loads every pattern
  //    `ORDER BY p.last_updated_at DESC, p.id`; `patterns.service.ts`'s own full-table pattern load
  //    shares the same eventual `WHERE user_id = ?`.
  //  - `inference_jobs(user_id, status)`: `worker.ts`'s `claimNext` (`WHERE status = 'queued' ...`)
  //    and its two crash-recovery sweeps (`WHERE status = 'running' AND attempts ...`) all filter on
  //    `status` alone today; `user_id` is the column #46 adds in front of it.
  //  - `experiments(user_id, status)`: `experiments.service.ts`'s `WHERE status = 'active'`, used by
  //    both `startExperiment`'s one-active-experiment check and `getActive`.
  //  - `pattern_withdrawals(user_id, superseded_at)`: `patterns.service.ts#listWithdrawals`'s
  //    `WHERE superseded_at IS NULL` — the "notices still current" filter every read of this table
  //    already applies.
  //
  // Left out, deliberately, rather than added speculatively: every junction/child table this
  // migration also gives a `user_id` (`entry_feelings`, `entry_topics`, `pattern_entries`,
  // `entry_topic_feelings`, `guiding_question_answers`, and `topics`/`csv_imports`/`diary_meta`).
  // Each is looked up today by the id of the parent row it hangs off (`entry_id`, `topic_id`,
  // `pattern_id`, or — for `diary_meta` — its own primary key), and every one of those lookups is
  // already covered by an existing `PRIMARY KEY`. No query in `src/` today scans any of them by
  // `user_id` alone, so an index led by it would be speculating about a query #46 has not written
  // yet — exactly what this ticket's own instructions say to leave out.
  `CREATE INDEX idx_diary_entries_user_date ON diary_entries (user_id, entry_date)`,
  `CREATE INDEX idx_patterns_user_updated ON patterns (user_id, last_updated_at)`,
  `CREATE INDEX idx_inference_jobs_user_status ON inference_jobs (user_id, status)`,
  `CREATE INDEX idx_experiments_user_status ON experiments (user_id, status)`,
  `CREATE INDEX idx_pattern_withdrawals_user_superseded ON pattern_withdrawals (user_id, superseded_at)`,
];

/**
 * The DDL that brings an older diary up to `SCHEMA_STATEMENTS`.
 *
 * It lives here because this file is the only one permitted to contain DDL, and it is executed by
 * exactly one entry point: `npm run migrate-db`. Like `init-db` that is a deliberate act the user
 * performs, not something the server does on startup — the server still refuses to alter a diary
 * and still fails loudly against one it cannot interpret.
 *
 * Every statement is additive and guarded — by `IF NOT EXISTS`, or by naming the table and column
 * it adds so it can be skipped when that column is already present — so running it twice is a
 * no-op. Nothing here drops, renames, or rewrites a column that holds diary content, and no
 * statement below touches a row the user wrote.
 */
export interface MigrationStatement {
  sql: string;
  /**
   * When set, the statement is an `ADD COLUMN` and is skipped if `table` already has `column`.
   * SQLite has no `ADD COLUMN IF NOT EXISTS`, so the guard is an inspection rather than a clause.
   */
  table?: string;
  column?: string;
  /**
   * For a guard `table`/`column` presence cannot express — a constraint change via table rebuild
   * (M-1b step 2, #46's `topics` unique-index rebuild below is the one user of this) has no new
   * column to check for, since every column it touches already existed. Return `true` to skip.
   * Checked instead of, never alongside, `table`/`column`.
   */
  skipIf?: (db: Database.Database) => boolean;
}

/**
 * `true` once `topics` already carries the `UNIQUE (user_id, name)` constraint the rebuild below
 * installs — read directly off `sqlite_master.sql`, the table's own stored `CREATE TABLE` text,
 * rather than a column-presence check (`topics.user_id` exists either way — see the rebuild
 * block's own comment for why that rules out the usual guard shape).
 */
function topicsAlreadyRebuilt(db: Database.Database): boolean {
  const row = db
    .prepare(`SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'topics'`)
    .get() as { sql: string } | undefined;
  return !!row?.sql && /UNIQUE\s*\(\s*user_id\s*,\s*name\s*\)/i.test(row.sql);
}

export const MIGRATION_STATEMENTS: MigrationStatement[] = [
  {
    sql: `CREATE TABLE IF NOT EXISTS feeling_groups (
              "key" VARCHAR(32) NOT NULL,
              label VARCHAR(64) NOT NULL,
              valence VARCHAR(16) NOT NULL,
              sort_order INTEGER NOT NULL,
              PRIMARY KEY ("key")
            )`,
  },
  {
    // `user_id` (M-1b, #134) is baked in here for the diary old enough to be missing this table
    // outright; the far more common case — a diary that already has it — is covered by the
    // guarded `ALTER TABLE` in the M-1b block below, which this `CREATE TABLE IF NOT EXISTS` is a
    // no-op against.
    sql: `CREATE TABLE IF NOT EXISTS entry_feelings (
              entry_id VARCHAR(36) NOT NULL,
              user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
              feeling_key VARCHAR(32) NOT NULL,
              position INTEGER NOT NULL,
              PRIMARY KEY (entry_id, feeling_key),
              FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
              FOREIGN KEY(feeling_key) REFERENCES feelings ("key"),
              FOREIGN KEY(user_id) REFERENCES users (id)
            )`,
  },
  {
    sql: `ALTER TABLE feelings ADD COLUMN group_key VARCHAR(32) NOT NULL DEFAULT ''`,
    table: 'feelings',
    column: 'group_key',
  },
  {
    sql: `ALTER TABLE feelings ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0`,
    table: 'feelings',
    column: 'sort_order',
  },

  // --- Withdrawal notices (A2) -----------------------------------------------------------------
  // Pattern identity, counts, a reason and timestamps. No diary text, ever (A2-08).
  {
    // `user_id` (M-1b, #134): see the note on the `entry_feelings` statement above — this covers
    // only the diary old enough to lack the table entirely; the guarded `ALTER TABLE` below covers
    // the common case.
    sql: `CREATE TABLE IF NOT EXISTS pattern_withdrawals (
              id VARCHAR(36) NOT NULL,
              user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
              pattern_key VARCHAR(160) NOT NULL,
              topic_id VARCHAR(36) NOT NULL,
              topic_name VARCHAR(128) NOT NULL,
              feeling_key VARCHAR(32) NOT NULL,
              kind VARCHAR(16) NOT NULL,
              previous_count INTEGER NOT NULL,
              new_count INTEGER NOT NULL,
              reason VARCHAR(32) NOT NULL,
              detail_text VARCHAR(512) NOT NULL,
              withdrawn_at DATETIME NOT NULL,
              superseded_at DATETIME,
              PRIMARY KEY (id),
              FOREIGN KEY(user_id) REFERENCES users (id)
            )`,
  },

  // --- Small key/value facts about the diary itself (A2-07's "since you last looked") -----------
  // `user_id` and the composite primary key (M-1b, #134) are baked in here only for the diary old
  // enough to lack this table entirely — a diary that already has it (every real one today) is
  // rebuilt by the dedicated `diary_meta` ownership migration further below, which a `CREATE TABLE
  // IF NOT EXISTS` cannot express: SQLite has no `ALTER TABLE ... ADD PRIMARY KEY`, and this
  // table's key stops meaning what it used to mean the moment two users can each hold their own
  // `pattern_echo_log` row.
  {
    sql: `CREATE TABLE IF NOT EXISTS diary_meta (
              user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
              "key" VARCHAR(64) NOT NULL,
              value TEXT NOT NULL,
              PRIMARY KEY (user_id, "key"),
              FOREIGN KEY(user_id) REFERENCES users (id)
            )`,
  },

  // --- Windowed counts, recency labelling and lift (I3, A3, I1, I2) -----------------------------
  // Defaults matter: an existing pattern row keeps working the moment the column appears, and the
  // first recompute overwrites every one of them with a measured value.
  {
    sql: `ALTER TABLE patterns ADD COLUMN kind VARCHAR(16) NOT NULL DEFAULT 'forward'`,
    table: 'patterns',
    column: 'kind',
  },
  {
    sql: `ALTER TABLE patterns ADD COLUMN lifetime_count INTEGER NOT NULL DEFAULT 0`,
    table: 'patterns',
    column: 'lifetime_count',
  },
  {
    sql: `ALTER TABLE patterns ADD COLUMN status VARCHAR(16) NOT NULL DEFAULT 'active'`,
    table: 'patterns',
    column: 'status',
  },
  {
    sql: `ALTER TABLE patterns ADD COLUMN last_occurrence_date DATE`,
    table: 'patterns',
    column: 'last_occurrence_date',
  },
  {
    sql: `ALTER TABLE patterns ADD COLUMN present_count INTEGER NOT NULL DEFAULT 0`,
    table: 'patterns',
    column: 'present_count',
  },
  {
    sql: `ALTER TABLE patterns ADD COLUMN present_total INTEGER NOT NULL DEFAULT 0`,
    table: 'patterns',
    column: 'present_total',
  },
  {
    sql: `ALTER TABLE patterns ADD COLUMN absent_count INTEGER NOT NULL DEFAULT 0`,
    table: 'patterns',
    column: 'absent_count',
  },
  {
    sql: `ALTER TABLE patterns ADD COLUMN absent_total INTEGER NOT NULL DEFAULT 0`,
    table: 'patterns',
    column: 'absent_total',
  },
  { sql: `ALTER TABLE patterns ADD COLUMN lift REAL`, table: 'patterns', column: 'lift' },
  {
    sql: `ALTER TABLE patterns ADD COLUMN comparison_reason VARCHAR(32)`,
    table: 'patterns',
    column: 'comparison_reason',
  },
  {
    sql: `ALTER TABLE patterns ADD COLUMN base_rate REAL NOT NULL DEFAULT 0`,
    table: 'patterns',
    column: 'base_rate',
  },
  {
    sql: `ALTER TABLE patterns ADD COLUMN is_strong BOOLEAN NOT NULL DEFAULT 0`,
    table: 'patterns',
    column: 'is_strong',
  },
  {
    sql: `ALTER TABLE patterns ADD COLUMN confounders JSON NOT NULL DEFAULT '[]'`,
    table: 'patterns',
    column: 'confounders',
  },

  // --- The optional intensity dial (I6) ---------------------------------------------------------
  // Nullable on purpose: intensity is optional by requirement (I6-01), and an entry whose feeling
  // the user never rated must be indistinguishable from one written before the dial existed.
  {
    sql: `ALTER TABLE diary_entries ADD COLUMN feeling_intensity INTEGER`,
    table: 'diary_entries',
    column: 'feeling_intensity',
  },

  // --- One intensity per feeling, not one per entry (I6 revisited) -------------------------------
  // The dial started as a single column on the entry because it graded "the primary feeling". That
  // only ever let someone rate the first word they picked: an entry that is *grateful and anxious*
  // could say how strongly it was grateful and had no way to say anything about the anxious half.
  // Intensity belongs to the feeling it was set on, so it lives beside the feeling.
  //
  // `diary_entries.feeling_intensity` stays, mirroring the primary feeling's value. The calendar
  // cell and every client built before this change read it, and it is cheaper to keep one derived
  // column honest than to make every reader join.
  {
    sql: `ALTER TABLE entry_feelings ADD COLUMN intensity INTEGER`,
    table: 'entry_feelings',
    column: 'intensity',
  },

  // --- N-of-1 experiments (R-3a) ------------------------------------------------------------
  {
    // `user_id` (M-1b, #134): see the note on the `entry_feelings` statement above.
    sql: `CREATE TABLE IF NOT EXISTS experiments (
              id VARCHAR(36) NOT NULL,
              user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
              pattern_topic VARCHAR(128) NOT NULL,
              pattern_feeling VARCHAR(32) NOT NULL,
              hypothesis_kind VARCHAR(16) NOT NULL,
              start_date DATE NOT NULL,
              end_date DATE NOT NULL,
              status VARCHAR(16) NOT NULL DEFAULT 'active',
              created_at DATETIME NOT NULL,
              PRIMARY KEY (id),
              FOREIGN KEY(pattern_feeling) REFERENCES feelings ("key"),
              FOREIGN KEY(user_id) REFERENCES users (id)
            )`,
  },

  // --- Mixed-valence pairing (E-1a) -----------------------------------------------------------
  {
    // `user_id` (M-1b, #134): see the note on the `entry_feelings` statement above.
    sql: `CREATE TABLE IF NOT EXISTS entry_topic_feelings (
              entry_id VARCHAR(36) NOT NULL,
              topic_id VARCHAR(36) NOT NULL,
              feeling_key VARCHAR(32) NOT NULL,
              user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
              source VARCHAR(16) NOT NULL,
              PRIMARY KEY (entry_id, topic_id, feeling_key),
              FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
              FOREIGN KEY(topic_id) REFERENCES topics (id) ON DELETE CASCADE,
              FOREIGN KEY(feeling_key) REFERENCES feelings ("key"),
              FOREIGN KEY(user_id) REFERENCES users (id)
            )`,
  },

  // --- Per-pattern narration attempt state (#88) ------------------------------------------------
  // The narration worker retries a rejected suggestion with exponential backoff and gives up after
  // a cap (`src/insights/constants.ts`), rather than hammering the model on the same pattern every
  // idle tick. Both columns are reset to their defaults by `PatternsService.storeCandidates`
  // whenever a pattern's counts change and its suggestion reverts to the template, so a pattern
  // that becomes narratable again always gets a fresh set of attempts.
  {
    sql: `ALTER TABLE patterns ADD COLUMN narration_attempts INTEGER NOT NULL DEFAULT 0`,
    table: 'patterns',
    column: 'narration_attempts',
  },
  {
    sql: `ALTER TABLE patterns ADD COLUMN narration_next_attempt_at DATETIME`,
    table: 'patterns',
    column: 'narration_next_attempt_at',
  },

  // --- Import provenance and idempotency (L-1b, #35) ---------------------------------------------
  // `DEFAULT 'app'` backfills every existing row the instant the column appears: a diary migrated
  // today has never imported anything, so every entry it already holds was written through the
  // normal compose flow.
  {
    sql: `ALTER TABLE diary_entries ADD COLUMN origin VARCHAR(16) NOT NULL DEFAULT 'app'`,
    table: 'diary_entries',
    column: 'origin',
  },
  {
    // `user_id` (M-1b, #134): see the note on the `entry_feelings` statement above.
    // `content_hash` stays the bare primary key — see this file's top-of-file M-1b step 2 (#46)
    // note on why that per-user uniqueness fix is deliberately left to a follow-up ticket.
    sql: `CREATE TABLE IF NOT EXISTS csv_imports (
              content_hash VARCHAR(64) NOT NULL,
              user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}',
              source VARCHAR(16) NOT NULL,
              imported_at DATETIME NOT NULL,
              entry_count INTEGER NOT NULL,
              report_json JSON NOT NULL,
              PRIMARY KEY (content_hash),
              FOREIGN KEY(user_id) REFERENCES users (id)
            )`,
  },

  // --- Multi-tenant identity (M-1a, #45) ----------------------------------------------------------
  // See the matching comment in SCHEMA_STATEMENTS above. `migrateDiary` (`./migrate.ts`) inserts the
  // default user row right after these two tables are created, in the same transaction — a diary
  // migrated today has never had accounts, so every table these tickets go on to scope belongs to
  // that one user.
  {
    sql: `CREATE TABLE IF NOT EXISTS users (
              id VARCHAR(36) NOT NULL,
              email VARCHAR(256) NOT NULL,
              password_hash VARCHAR(256) NOT NULL,
              created_at DATETIME NOT NULL,
              PRIMARY KEY (id),
              UNIQUE (email)
            )`,
  },
  {
    sql: `CREATE TABLE IF NOT EXISTS sessions (
              token_hash VARCHAR(64) NOT NULL,
              user_id VARCHAR(36) NOT NULL,
              created_at DATETIME NOT NULL,
              expires_at DATETIME NOT NULL,
              PRIMARY KEY (token_hash),
              FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
            )`,
  },

  // --- Server-side entitlements (M-2, #47) --------------------------------------------------------
  // See the matching comment in SCHEMA_STATEMENTS above. Unlike `users`, nothing here inserts a
  // default row for `DEFAULT_USER_ID` (or for any other existing account): a diary migrated today
  // has never recorded a purchase, and "no row" already reads as free through
  // `EntitlementsService#getEntitlement`, so there is nothing to backfill.
  {
    sql: `CREATE TABLE IF NOT EXISTS entitlements (
              user_id VARCHAR(36) NOT NULL,
              tier VARCHAR(16) NOT NULL DEFAULT 'free',
              source VARCHAR(16) NOT NULL DEFAULT 'manual',
              expires_at DATETIME,
              updated_at DATETIME NOT NULL,
              PRIMARY KEY (user_id),
              FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
            )`,
  },

  // --- Multi-tenant scoping, step 1 (M-1b, #134) ----------------------------------------------
  // `user_id VARCHAR(36) NOT NULL DEFAULT '<DEFAULT_USER_ID>' REFERENCES users (id)` on every
  // table this file's top-of-file note classifies as user data. The `ADD COLUMN`'s own default is
  // the backfill: SQLite fills every existing row with it the instant the column exists, in the
  // same statement, so there is no separate `UPDATE` to keep idempotent or to run in the right
  // order relative to the column's own arrival.
  //
  // Placed after `users` above, not because `ADD COLUMN ... REFERENCES` requires the target table
  // to already exist (SQLite never validates that at DDL time — proven in this ticket's own
  // testing), but because it reads correctly: these columns exist to point at rows in the table
  // just created.
  //
  // `migrateDiary` (`./migrate.ts`) runs this whole migration with `foreign_keys = OFF`, which is
  // what makes the statements below legal at all: SQLite refuses `ALTER TABLE ... ADD COLUMN` for
  // a column that carries both a `REFERENCES` clause and a non-NULL default while foreign keys are
  // enforced ("Cannot add a REFERENCES column with non-NULL default value") — confirmed against
  // this project's actual `better-sqlite3` version, which (unlike the `sqlite3` CLI) defaults
  // `foreign_keys` to **on** for a fresh raw connection, exactly the trap #83's agent hit. Turning
  // it off here matches the posture the running server already has permanently (`database.ts`) and
  // the golden-fixture builder already needs (`build-golden-db.ts`) — it does not newly relax
  // anything a real diary depended on.
  {
    sql: `ALTER TABLE topics ADD COLUMN user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}' REFERENCES users (id)`,
    table: 'topics',
    column: 'user_id',
  },
  {
    sql: `ALTER TABLE diary_entries ADD COLUMN user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}' REFERENCES users (id)`,
    table: 'diary_entries',
    column: 'user_id',
  },
  {
    sql: `ALTER TABLE entry_feelings ADD COLUMN user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}' REFERENCES users (id)`,
    table: 'entry_feelings',
    column: 'user_id',
  },
  {
    sql: `ALTER TABLE guiding_question_answers ADD COLUMN user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}' REFERENCES users (id)`,
    table: 'guiding_question_answers',
    column: 'user_id',
  },
  {
    sql: `ALTER TABLE entry_topics ADD COLUMN user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}' REFERENCES users (id)`,
    table: 'entry_topics',
    column: 'user_id',
  },
  {
    sql: `ALTER TABLE patterns ADD COLUMN user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}' REFERENCES users (id)`,
    table: 'patterns',
    column: 'user_id',
  },
  {
    sql: `ALTER TABLE pattern_entries ADD COLUMN user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}' REFERENCES users (id)`,
    table: 'pattern_entries',
    column: 'user_id',
  },
  {
    sql: `ALTER TABLE pattern_withdrawals ADD COLUMN user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}' REFERENCES users (id)`,
    table: 'pattern_withdrawals',
    column: 'user_id',
  },
  {
    sql: `ALTER TABLE experiments ADD COLUMN user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}' REFERENCES users (id)`,
    table: 'experiments',
    column: 'user_id',
  },
  {
    sql: `ALTER TABLE inference_jobs ADD COLUMN user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}' REFERENCES users (id)`,
    table: 'inference_jobs',
    column: 'user_id',
  },
  {
    sql: `ALTER TABLE entry_topic_feelings ADD COLUMN user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}' REFERENCES users (id)`,
    table: 'entry_topic_feelings',
    column: 'user_id',
  },
  {
    sql: `ALTER TABLE csv_imports ADD COLUMN user_id VARCHAR(36) NOT NULL DEFAULT '${DEFAULT_USER_ID}' REFERENCES users (id)`,
    table: 'csv_imports',
    column: 'user_id',
  },

  // --- `topics.name` uniqueness: a constraint rebuild, not an `ADD COLUMN` (M-1b step 2, #46) -----
  // See this file's top-of-file note for why this one, unlike `csv_imports.content_hash`, is fixed
  // now rather than deferred: two ordinary accounts both mentioning "coffee" is the routine case
  // for two unrelated diaries, not a rare edge case, and the bare `UNIQUE (name)` constraint turned
  // that routine case into a `GET /insights` 500 for whichever account's `INSERT` ran second.
  //
  // `user_id` already exists on this table by the time this block runs (the `ALTER TABLE topics
  // ADD COLUMN user_id ...` statement above), so — unlike `diary_meta`'s rebuild — a column-presence
  // guard cannot tell "already rebuilt" apart from "not yet rebuilt": both states have the column.
  // `skipIf` instead inspects `sqlite_master.sql` for this table directly, checking for the new
  // constraint's own text — the same "ask the database what shape it actually is" principle, just
  // aimed at a constraint instead of a column.
  {
    sql: `CREATE TABLE topics_new (
              id VARCHAR(36) NOT NULL,
              user_id VARCHAR(36) NOT NULL,
              name VARCHAR(128) NOT NULL,
              aliases JSON NOT NULL,
              first_seen_at DATETIME NOT NULL,
              last_seen_at DATETIME NOT NULL,
              PRIMARY KEY (id),
              UNIQUE (user_id, name),
              FOREIGN KEY(user_id) REFERENCES users (id)
            )`,
    skipIf: topicsAlreadyRebuilt,
  },
  {
    sql: `INSERT INTO topics_new (id, user_id, name, aliases, first_seen_at, last_seen_at)
          SELECT id, user_id, name, aliases, first_seen_at, last_seen_at FROM topics`,
    skipIf: topicsAlreadyRebuilt,
  },
  { sql: `DROP TABLE topics`, skipIf: topicsAlreadyRebuilt },
  { sql: `ALTER TABLE topics_new RENAME TO topics`, skipIf: topicsAlreadyRebuilt },

  // --- `diary_meta` ownership: a primary-key rebuild, not an `ADD COLUMN` (M-1b, #134) ------------
  // Every table above keeps its primary key and only gains a column. `diary_meta` cannot: its key
  // was the bare `"key"` string, which stops being unique the moment a second user can hold a
  // `pattern_echo_log` row of their own, so the key must become the composite `(user_id, "key")` —
  // and SQLite has no `ALTER TABLE ... ADD PRIMARY KEY` or `DROP PRIMARY KEY`, so changing one
  // means rebuilding the table: create it under the new shape, copy every row across (owned by
  // `DEFAULT_USER_ID` — the only owner a diary predating accounts could have), drop the old table,
  // and rename the new one into its place.
  //
  // All four statements share the same guard (`table: 'diary_meta', column: 'user_id'`), which is
  // what makes the sequence idempotent as a whole even though only the first statement's precise
  // wording names that pair: the guard re-inspects `diary_meta` immediately before *each*
  // statement, so on a second run the very first statement already finds `user_id` present (this
  // rebuild having renamed `diary_meta_new` over it the first time) and every statement below is
  // skipped in turn — including the final rename, which never gets a table to rename away from.
  {
    sql: `CREATE TABLE diary_meta_new (
              user_id VARCHAR(36) NOT NULL,
              "key" VARCHAR(64) NOT NULL,
              value TEXT NOT NULL,
              PRIMARY KEY (user_id, "key"),
              FOREIGN KEY(user_id) REFERENCES users (id)
            )`,
    table: 'diary_meta',
    column: 'user_id',
  },
  {
    sql: `INSERT INTO diary_meta_new (user_id, "key", value)
          SELECT '${DEFAULT_USER_ID}', "key", value FROM diary_meta`,
    table: 'diary_meta',
    column: 'user_id',
  },
  {
    sql: `DROP TABLE diary_meta`,
    table: 'diary_meta',
    column: 'user_id',
  },
  {
    sql: `ALTER TABLE diary_meta_new RENAME TO diary_meta`,
    table: 'diary_meta',
    column: 'user_id',
  },

  // --- The first indexes in this schema, for a migrated diary (M-1b, #134) -----------------------
  // Identical to the five in `SCHEMA_STATEMENTS` — see that block's comment for which query in
  // `src/` each one is for. `CREATE INDEX IF NOT EXISTS` is its own idempotency guard, unlike the
  // `ADD COLUMN` statements above: SQLite does support `IF NOT EXISTS` for an index, just not for a
  // column, so these need no `table`/`column` pair.
  {
    sql: `CREATE INDEX IF NOT EXISTS idx_diary_entries_user_date ON diary_entries (user_id, entry_date)`,
  },
  {
    sql: `CREATE INDEX IF NOT EXISTS idx_patterns_user_updated ON patterns (user_id, last_updated_at)`,
  },
  {
    sql: `CREATE INDEX IF NOT EXISTS idx_inference_jobs_user_status ON inference_jobs (user_id, status)`,
  },
  {
    sql: `CREATE INDEX IF NOT EXISTS idx_experiments_user_status ON experiments (user_id, status)`,
  },
  {
    sql: `CREATE INDEX IF NOT EXISTS idx_pattern_withdrawals_user_superseded ON pattern_withdrawals (user_id, superseded_at)`,
  },
];

/**
 * The one DDL statement for `alembic_version` — the inert table an old migration tool leaves
 * behind (see `tests/fixtures/README.md`). It is not part of this schema: real diaries may carry
 * one from before this backend existed, `assertCompatible` (`compatibility.ts`) ignores it
 * outright, and neither `SCHEMA_STATEMENTS` nor `MIGRATION_STATEMENTS` above create it — a diary
 * this backend creates or migrates has no business inventing history for a tool it never ran.
 *
 * Kept here rather than inlined elsewhere so this file stays the *only* one with DDL text, per the
 * comment at the top. The sole caller is `build-golden-db.ts`, which builds a disposable test
 * fixture that must resemble a real diary down to this detail.
 */
export const ALEMBIC_VERSION_STATEMENT = `CREATE TABLE alembic_version (
     version_num VARCHAR(32) NOT NULL,
     PRIMARY KEY (version_num)
   )`;
