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
  `CREATE TABLE feelings (
     "key" VARCHAR(32) NOT NULL,
     label VARCHAR(64) NOT NULL,
     valence VARCHAR(16) NOT NULL,
     PRIMARY KEY ("key")
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
     PRIMARY KEY (id),
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
];
