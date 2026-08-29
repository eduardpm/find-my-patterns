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
     name VARCHAR(128) NOT NULL,
     aliases JSON NOT NULL,
     first_seen_at DATETIME NOT NULL,
     last_seen_at DATETIME NOT NULL,
     PRIMARY KEY (id),
     UNIQUE (name)
   )`,

  `CREATE TABLE diary_entries (
     id VARCHAR(36) NOT NULL,
     created_at DATETIME NOT NULL,
     updated_at DATETIME NOT NULL,
     entry_date DATE NOT NULL,
     mode VARCHAR(16) NOT NULL,
     raw_text TEXT NOT NULL,
     feeling_key VARCHAR(32),
     feeling_source VARCHAR(16) NOT NULL,
     version INTEGER DEFAULT '1' NOT NULL,
     feeling_intensity INTEGER,
     PRIMARY KEY (id),
     FOREIGN KEY(feeling_key) REFERENCES feelings ("key")
   )`,

  `CREATE TABLE entry_feelings (
     entry_id VARCHAR(36) NOT NULL,
     feeling_key VARCHAR(32) NOT NULL,
     position INTEGER NOT NULL,
     intensity INTEGER,
     PRIMARY KEY (entry_id, feeling_key),
     FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
     FOREIGN KEY(feeling_key) REFERENCES feelings ("key")
   )`,

  `CREATE TABLE guiding_question_answers (
     id VARCHAR(36) NOT NULL,
     entry_id VARCHAR(36) NOT NULL,
     question_key VARCHAR(64) NOT NULL,
     question_text_snapshot VARCHAR(256) NOT NULL,
     answer_text VARCHAR(1024) NOT NULL,
     order_index INTEGER NOT NULL,
     PRIMARY KEY (id),
     FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
     FOREIGN KEY(question_key) REFERENCES guiding_questions ("key")
   )`,

  `CREATE TABLE entry_topics (
     entry_id VARCHAR(36) NOT NULL,
     topic_id VARCHAR(36) NOT NULL,
     extracted_by VARCHAR(16),
     PRIMARY KEY (entry_id, topic_id),
     FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
     FOREIGN KEY(topic_id) REFERENCES topics (id) ON DELETE CASCADE
   )`,

  `CREATE TABLE patterns (
     id VARCHAR(36) NOT NULL,
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
     PRIMARY KEY (id),
     FOREIGN KEY(feeling_key) REFERENCES feelings ("key"),
     FOREIGN KEY(topic_id) REFERENCES topics (id)
   )`,

  `CREATE TABLE pattern_entries (
     pattern_id VARCHAR(36) NOT NULL,
     entry_id VARCHAR(36) NOT NULL,
     PRIMARY KEY (pattern_id, entry_id),
     FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
     FOREIGN KEY(pattern_id) REFERENCES patterns (id) ON DELETE CASCADE
   )`,

  `CREATE TABLE inference_jobs (
     id VARCHAR(36) NOT NULL,
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
     FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE
   )`,

  `CREATE TABLE pattern_withdrawals (
     id VARCHAR(36) NOT NULL,
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
     PRIMARY KEY (id)
   )`,

  `CREATE TABLE diary_meta (
     "key" VARCHAR(64) NOT NULL,
     value TEXT NOT NULL,
     PRIMARY KEY ("key")
   )`,
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
    sql: `CREATE TABLE IF NOT EXISTS entry_feelings (
              entry_id VARCHAR(36) NOT NULL,
              feeling_key VARCHAR(32) NOT NULL,
              position INTEGER NOT NULL,
              PRIMARY KEY (entry_id, feeling_key),
              FOREIGN KEY(entry_id) REFERENCES diary_entries (id) ON DELETE CASCADE,
              FOREIGN KEY(feeling_key) REFERENCES feelings ("key")
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
    sql: `CREATE TABLE IF NOT EXISTS pattern_withdrawals (
              id VARCHAR(36) NOT NULL,
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
              PRIMARY KEY (id)
            )`,
  },

  // --- Small key/value facts about the diary itself (A2-07's "since you last looked") -----------
  {
    sql: `CREATE TABLE IF NOT EXISTS diary_meta (
              "key" VARCHAR(64) NOT NULL,
              value TEXT NOT NULL,
              PRIMARY KEY ("key")
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
];
