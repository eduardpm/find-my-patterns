import type { DiaryDatabase } from './database';
import { decodeDate, decodeDateTime, decodeJson } from './codecs';
import { MAX_INTENSITY, MIN_INTENSITY } from '../insights/constants';

/** Every value `diary_entries.feeling_source` is allowed to hold. */
const FEELING_SOURCES = ['unset', 'suggested', 'confirmed', 'overridden'];

/** Every value `diary_entries.origin` is allowed to hold (L-1b, #35). */
const ENTRY_ORIGINS = ['app', 'daylio_import'];

/** Every value `entry_topic_feelings.source` is allowed to hold (E-1a) — no `'unset'`: a pairing
 * that was never proposed or chosen simply has no row, the same way a topic no entry mentions has
 * no `entry_topics` row. */
const PAIRING_SOURCES = ['suggested', 'confirmed', 'overridden'];

/**
 * FR-018 — refuse to run against a diary this backend cannot fully interpret.
 *
 * It exists because the schema is adopted rather than owned
 * (FR-021) — nothing guarantees the file on disk matches what this code expects, and the failure
 * mode without a check is far worse than a startup error: the app serves a partial diary and the
 * user believes entries are gone.
 */

const REQUIRED: Record<string, Record<string, string>> = {
  feeling_groups: {
    key: 'VARCHAR(32)',
    label: 'VARCHAR(64)',
    valence: 'VARCHAR(16)',
    sort_order: 'INTEGER',
  },
  feelings: {
    key: 'VARCHAR(32)',
    label: 'VARCHAR(64)',
    valence: 'VARCHAR(16)',
    group_key: 'VARCHAR(32)',
    sort_order: 'INTEGER',
  },
  // --- Multi-tenant scoping, step 1 (M-1b, #134) --------------------------------------------------
  // Every table below this comment through `csv_imports` gained a `user_id VARCHAR(36)` column;
  // see `schema.ts`'s top-of-file note for the full table-by-table classification (reference
  // vocabulary and already-user-keyed tables are deliberately not touched). Registering it here is
  // what `assertCompatible` needs to keep treating a migrated diary as fully interpreted — an
  // unregistered column is invisible to FR-018, not merely unchecked.
  entry_feelings: {
    entry_id: 'VARCHAR(36)',
    user_id: 'VARCHAR(36)',
    feeling_key: 'VARCHAR(32)',
    position: 'INTEGER',
    intensity: 'INTEGER',
  },
  guiding_questions: {
    key: 'VARCHAR(64)',
    category: 'VARCHAR(32)',
    prompt_text: 'VARCHAR(256)',
    trigger_keywords: 'JSON',
    is_mandatory: 'BOOLEAN',
  },
  topics: {
    id: 'VARCHAR(36)',
    user_id: 'VARCHAR(36)',
    name: 'VARCHAR(128)',
    aliases: 'JSON',
    first_seen_at: 'DATETIME',
    last_seen_at: 'DATETIME',
  },
  diary_entries: {
    id: 'VARCHAR(36)',
    user_id: 'VARCHAR(36)',
    created_at: 'DATETIME',
    updated_at: 'DATETIME',
    entry_date: 'DATE',
    mode: 'VARCHAR(16)',
    raw_text: 'TEXT',
    feeling_key: 'VARCHAR(32)',
    feeling_source: 'VARCHAR(16)',
    version: 'INTEGER',
    feeling_intensity: 'INTEGER',
    origin: 'VARCHAR(16)',
  },
  guiding_question_answers: {
    id: 'VARCHAR(36)',
    user_id: 'VARCHAR(36)',
    entry_id: 'VARCHAR(36)',
    question_key: 'VARCHAR(64)',
    question_text_snapshot: 'VARCHAR(256)',
    answer_text: 'VARCHAR(1024)',
    order_index: 'INTEGER',
  },
  entry_topics: {
    entry_id: 'VARCHAR(36)',
    topic_id: 'VARCHAR(36)',
    user_id: 'VARCHAR(36)',
    extracted_by: 'VARCHAR(16)',
  },
  patterns: {
    id: 'VARCHAR(36)',
    user_id: 'VARCHAR(36)',
    topic_id: 'VARCHAR(36)',
    feeling_key: 'VARCHAR(32)',
    occurrence_count: 'INTEGER',
    narrative_text: 'VARCHAR(512)',
    suggestion_text: 'VARCHAR(512)',
    direction: 'VARCHAR(16)',
    first_detected_at: 'DATETIME',
    last_updated_at: 'DATETIME',
    kind: 'VARCHAR(16)',
    lifetime_count: 'INTEGER',
    status: 'VARCHAR(16)',
    last_occurrence_date: 'DATE',
    present_count: 'INTEGER',
    present_total: 'INTEGER',
    absent_count: 'INTEGER',
    absent_total: 'INTEGER',
    lift: 'REAL',
    comparison_reason: 'VARCHAR(32)',
    base_rate: 'REAL',
    is_strong: 'BOOLEAN',
    confounders: 'JSON',
    narration_attempts: 'INTEGER',
    narration_next_attempt_at: 'DATETIME',
  },
  pattern_entries: {
    pattern_id: 'VARCHAR(36)',
    entry_id: 'VARCHAR(36)',
    user_id: 'VARCHAR(36)',
  },
  pattern_withdrawals: {
    id: 'VARCHAR(36)',
    user_id: 'VARCHAR(36)',
    pattern_key: 'VARCHAR(160)',
    topic_id: 'VARCHAR(36)',
    topic_name: 'VARCHAR(128)',
    feeling_key: 'VARCHAR(32)',
    kind: 'VARCHAR(16)',
    previous_count: 'INTEGER',
    new_count: 'INTEGER',
    reason: 'VARCHAR(32)',
    detail_text: 'VARCHAR(512)',
    withdrawn_at: 'DATETIME',
    superseded_at: 'DATETIME',
  },
  // `key` alone is no longer the primary key (`schema.ts`'s M-1b note) — `assertCompatible` only
  // checks column presence/type here, not key-ness, so this entry is otherwise unchanged.
  diary_meta: { user_id: 'VARCHAR(36)', key: 'VARCHAR(64)', value: 'TEXT' },
  experiments: {
    id: 'VARCHAR(36)',
    user_id: 'VARCHAR(36)',
    pattern_topic: 'VARCHAR(128)',
    pattern_feeling: 'VARCHAR(32)',
    hypothesis_kind: 'VARCHAR(16)',
    start_date: 'DATE',
    end_date: 'DATE',
    status: 'VARCHAR(16)',
    created_at: 'DATETIME',
  },
  inference_jobs: {
    id: 'VARCHAR(36)',
    user_id: 'VARCHAR(36)',
    kind: 'VARCHAR(32)',
    entry_id: 'VARCHAR(36)',
    status: 'VARCHAR(16)',
    result_json: 'JSON',
    error_text: 'TEXT',
    attempts: 'INTEGER',
    created_at: 'DATETIME',
    started_at: 'DATETIME',
    completed_at: 'DATETIME',
  },
  entry_topic_feelings: {
    entry_id: 'VARCHAR(36)',
    topic_id: 'VARCHAR(36)',
    feeling_key: 'VARCHAR(32)',
    user_id: 'VARCHAR(36)',
    source: 'VARCHAR(16)',
  },
  csv_imports: {
    content_hash: 'VARCHAR(64)',
    user_id: 'VARCHAR(36)',
    source: 'VARCHAR(16)',
    imported_at: 'DATETIME',
    entry_count: 'INTEGER',
    report_json: 'JSON',
  },
  // --- Multi-tenant identity (M-1a, #45) --------------------------------------------------------
  users: {
    id: 'VARCHAR(36)',
    email: 'VARCHAR(256)',
    password_hash: 'VARCHAR(256)',
    created_at: 'DATETIME',
  },
  sessions: {
    token_hash: 'VARCHAR(64)',
    user_id: 'VARCHAR(36)',
    created_at: 'DATETIME',
    expires_at: 'DATETIME',
  },
  // --- Server-side entitlements (M-2, #47) ------------------------------------------------------
  entitlements: {
    user_id: 'VARCHAR(36)',
    tier: 'VARCHAR(16)',
    source: 'VARCHAR(16)',
    expires_at: 'DATETIME',
    updated_at: 'DATETIME',
  },
};

export class IncompatibleDiaryError extends Error {
  constructor(readonly problems: string[]) {
    super(
      `This diary cannot be fully interpreted, so the backend will not start (FR-018).\n` +
        problems.map((p) => `  - ${p}`).join('\n') +
        `\n\nNothing was modified. If this diary predates the grouped feeling vocabulary, run ` +
        `\`npm run migrate-db\` — it only adds reference data and never touches an entry. If this ` +
        `is meant to be a fresh start, create a new diary with \`npm run init-db\` — it will not ` +
        `overwrite an existing file.`,
    );
  }
}

export function assertCompatible(db: DiaryDatabase): void {
  const problems: string[] = [];

  const tables = new Set(
    (
      db.readonlyPragma(`SELECT name FROM sqlite_master WHERE type='table'`) as { name: string }[]
    ).map((r) => r.name),
  );

  for (const [table, columns] of Object.entries(REQUIRED)) {
    if (!tables.has(table)) {
      problems.push(`missing table "${table}"`);
      continue;
    }
    const present = new Map(
      (
        db.readonlyPragma(`SELECT name, type FROM pragma_table_info('${table}')`) as Array<{
          name: string;
          type: string;
        }>
      ).map((r) => [r.name, r.type.toUpperCase()]),
    );
    for (const [column, expectedType] of Object.entries(columns)) {
      const actualType = present.get(column);
      if (!actualType) {
        problems.push(`table "${table}" is missing column "${column}"`);
      } else if (actualType !== expectedType) {
        problems.push(
          `table "${table}" column "${column}" has type ${actualType}, expected ${expectedType}`,
        );
      }
    }
  }

  if (problems.length === 0) validateStoredValues(db, problems);

  if (problems.length > 0) throw new IncompatibleDiaryError(problems);
}

function validateStoredValues(db: DiaryDatabase, problems: string[]): void {
  const groupKeys = new Set(
    (db.prepare('SELECT "key" FROM feeling_groups').all() as Array<{ key: string }>).map(
      (row) => row.key,
    ),
  );
  if (groupKeys.size === 0) problems.push('feeling_groups contains no reference rows');

  const feelings = db.prepare('SELECT "key", valence, group_key FROM feelings').all() as Array<{
    key: string;
    valence: string;
    group_key: string;
  }>;
  const feelingKeys = new Set(feelings.map((row) => row.key));
  if (feelings.length === 0) problems.push('feelings contains no reference rows');
  for (const row of feelings) {
    if (!['positive', 'neutral', 'negative'].includes(row.valence)) {
      problems.push(`feelings contains an unsupported valence for key "${row.key}"`);
    }
    // A feeling outside every group would be unreachable in both clients, which show the
    // vocabulary group-first.
    if (!groupKeys.has(row.group_key)) {
      problems.push(`feelings key "${row.key}" belongs to unknown group "${row.group_key}"`);
    }
  }

  // --- Multi-tenant identity (M-1a, #45) ----------------------------------------------------------
  // Moved ahead of the table validators below (M-1b, #134): every one of them now also checks its
  // rows' `user_id` against this set, so it has to exist before the first of them runs.
  const userIds = new Set(
    (db.prepare('SELECT id FROM users').all() as Array<{ id: string }>).map((row) => row.id),
  );
  // Every table this migration touches assumes at least the default user exists — #46's `user_id`
  // foreign keys would otherwise have nothing to point at.
  if (userIds.size === 0) problems.push('users contains no rows (the default user is missing)');

  validateRows(
    'entry_feelings',
    db
      .prepare('SELECT entry_id AS id, user_id, feeling_key, position FROM entry_feelings')
      .all() as Array<Record<string, unknown>>,
    problems,
    (row) => {
      if (!userIds.has(String(row.user_id))) throw new Error('unknown user id');
      if (!feelingKeys.has(String(row.feeling_key))) throw new Error('unknown feeling key');
      if (!Number.isInteger(Number(row.position)) || Number(row.position) < 0) {
        throw new Error('invalid feeling position');
      }
    },
  );

  validateRows(
    'diary_entries',
    db
      .prepare(
        `SELECT id, user_id, created_at, updated_at, entry_date, mode, feeling_key, feeling_source,
                version, feeling_intensity, origin FROM diary_entries`,
      )
      .all() as Array<Record<string, unknown>>,
    problems,
    (row) => {
      if (!userIds.has(String(row.user_id))) throw new Error('unknown user id');
      decodeDateTime(String(row.created_at));
      decodeDateTime(String(row.updated_at));
      decodeDate(String(row.entry_date));
      if (!['guided', 'freeform'].includes(String(row.mode))) throw new Error('unsupported mode');
      if (!FEELING_SOURCES.includes(String(row.feeling_source))) {
        throw new Error('unsupported feeling source');
      }
      if (!ENTRY_ORIGINS.includes(String(row.origin))) {
        throw new Error('unsupported entry origin');
      }
      if (row.feeling_intensity !== null && row.feeling_intensity !== undefined) {
        const intensity = Number(row.feeling_intensity);
        if (
          !Number.isInteger(intensity) ||
          intensity < MIN_INTENSITY ||
          intensity > MAX_INTENSITY
        ) {
          throw new Error('invalid feeling intensity');
        }
      }
      if (row.feeling_key !== null && !feelingKeys.has(String(row.feeling_key))) {
        throw new Error('unknown feeling key');
      }
      if (!Number.isInteger(Number(row.version)) || Number(row.version) < 1) {
        throw new Error('invalid revision marker');
      }
    },
  );

  validateRows(
    'guiding_questions',
    db
      .prepare('SELECT "key" AS id, trigger_keywords, is_mandatory FROM guiding_questions')
      .all() as Array<Record<string, unknown>>,
    problems,
    (row) => {
      const keywords = decodeJson<unknown>(String(row.trigger_keywords));
      if (!Array.isArray(keywords) || !keywords.every((item) => typeof item === 'string')) {
        throw new Error('trigger keywords are not a string array');
      }
      if (![0, 1].includes(Number(row.is_mandatory))) throw new Error('invalid boolean');
    },
  );

  validateRows(
    'topics',
    db
      .prepare('SELECT id, user_id, aliases, first_seen_at, last_seen_at FROM topics')
      .all() as Array<Record<string, unknown>>,
    problems,
    (row) => {
      if (!userIds.has(String(row.user_id))) throw new Error('unknown user id');
      const aliases = decodeJson<unknown>(String(row.aliases));
      if (!Array.isArray(aliases) || !aliases.every((item) => typeof item === 'string')) {
        throw new Error('aliases are not a string array');
      }
      decodeDateTime(String(row.first_seen_at));
      decodeDateTime(String(row.last_seen_at));
    },
  );

  validateRows(
    'patterns',
    db
      .prepare(
        `SELECT id, user_id, feeling_key, occurrence_count, direction, first_detected_at,
                last_updated_at, kind, status FROM patterns`,
      )
      .all() as Array<Record<string, unknown>>,
    problems,
    (row) => {
      if (!userIds.has(String(row.user_id))) throw new Error('unknown user id');
      if (!feelingKeys.has(String(row.feeling_key))) throw new Error('unknown feeling key');
      // Zero is valid and meaningful: a **historical** pattern is one whose windowed count has
      // fallen to nothing while its lifetime evidence stands (I3-03/I3-05). Rejecting zero here
      // would make the engine's own output unreadable to the next start-up.
      if (!Number.isInteger(Number(row.occurrence_count)) || Number(row.occurrence_count) < 0) {
        throw new Error('invalid occurrence count');
      }
      if (!['forward', 'inverse'].includes(String(row.kind)))
        throw new Error('invalid pattern kind');
      if (!['active', 'historical'].includes(String(row.status))) {
        throw new Error('invalid pattern status');
      }
      if (!['keep', 'change'].includes(String(row.direction))) throw new Error('invalid direction');
      decodeDateTime(String(row.first_detected_at));
      decodeDateTime(String(row.last_updated_at));
    },
  );

  validateRows(
    'experiments',
    db
      .prepare(
        `SELECT id, user_id, pattern_feeling, hypothesis_kind, start_date, end_date, status,
                created_at FROM experiments`,
      )
      .all() as Array<Record<string, unknown>>,
    problems,
    (row) => {
      if (!userIds.has(String(row.user_id))) throw new Error('unknown user id');
      if (!feelingKeys.has(String(row.pattern_feeling))) throw new Error('unknown feeling key');
      if (!['more_of', 'less_of'].includes(String(row.hypothesis_kind))) {
        throw new Error('invalid hypothesis kind');
      }
      if (!['active', 'finished', 'abandoned'].includes(String(row.status))) {
        throw new Error('invalid experiment status');
      }
      decodeDate(String(row.start_date));
      decodeDate(String(row.end_date));
      decodeDateTime(String(row.created_at));
    },
  );

  validateRows(
    'entry_topic_feelings',
    db
      .prepare(
        'SELECT entry_id AS id, topic_id, feeling_key, user_id, source FROM entry_topic_feelings',
      )
      .all() as Array<Record<string, unknown>>,
    problems,
    (row) => {
      if (!userIds.has(String(row.user_id))) throw new Error('unknown user id');
      if (!feelingKeys.has(String(row.feeling_key))) throw new Error('unknown feeling key');
      if (!PAIRING_SOURCES.includes(String(row.source)))
        throw new Error('unsupported pairing source');
    },
  );

  validateRows(
    'csv_imports',
    db
      .prepare(
        `SELECT content_hash AS id, user_id, source, imported_at, entry_count, report_json
         FROM csv_imports`,
      )
      .all() as Array<Record<string, unknown>>,
    problems,
    (row) => {
      if (!userIds.has(String(row.user_id))) throw new Error('unknown user id');
      decodeDateTime(String(row.imported_at));
      if (!Number.isInteger(Number(row.entry_count)) || Number(row.entry_count) < 0) {
        throw new Error('invalid entry count');
      }
      JSON.parse(String(row.report_json));
    },
  );

  validateRows(
    'users',
    db.prepare('SELECT id, email, created_at FROM users').all() as Array<Record<string, unknown>>,
    problems,
    (row) => {
      decodeDateTime(String(row.created_at));
      if (!String(row.email).includes('@')) throw new Error('email is missing "@"');
    },
  );

  validateRows(
    'sessions',
    db
      .prepare('SELECT token_hash AS id, user_id, created_at, expires_at FROM sessions')
      .all() as Array<Record<string, unknown>>,
    problems,
    (row) => {
      if (!userIds.has(String(row.user_id))) throw new Error('unknown user id');
      decodeDateTime(String(row.created_at));
      decodeDateTime(String(row.expires_at));
    },
  );

  // --- Server-side entitlements (M-2, #47) --------------------------------------------------------
  // No emptiness check, unlike `users` above: a diary with zero rows in this table is exactly the
  // steady state for every account that has never verified a purchase (`schema.ts`'s comment on
  // this table explains why absence, not a seeded `'free'` row, is what "everyone defaults to free"
  // means here).
  validateRows(
    'entitlements',
    db
      .prepare('SELECT user_id, tier, source, expires_at, updated_at FROM entitlements')
      .all() as Array<Record<string, unknown>>,
    problems,
    (row) => {
      if (!userIds.has(String(row.user_id))) throw new Error('unknown user id');
      if (!['free', 'premium'].includes(String(row.tier))) throw new Error('unsupported tier');
      if (!['play', 'manual'].includes(String(row.source))) {
        throw new Error('unsupported entitlement source');
      }
      // NULL is the lifetime marker (schema.ts) — only a real value needs to parse as a datetime.
      if (row.expires_at !== null) decodeDateTime(String(row.expires_at));
      decodeDateTime(String(row.updated_at));
    },
  );

  validateRows(
    'inference_jobs',
    db
      .prepare(
        `SELECT id, user_id, kind, status, result_json, attempts, created_at, started_at,
                completed_at FROM inference_jobs`,
      )
      .all() as Array<Record<string, unknown>>,
    problems,
    (row) => {
      if (!userIds.has(String(row.user_id))) throw new Error('unknown user id');
      if (!['entry_analysis', 'transcript_format'].includes(String(row.kind))) {
        throw new Error('unsupported job kind');
      }
      if (!['queued', 'running', 'completed', 'failed'].includes(String(row.status))) {
        throw new Error('unsupported job status');
      }
      if (!Number.isInteger(Number(row.attempts)) || Number(row.attempts) < 0) {
        throw new Error('invalid attempt count');
      }
      decodeDateTime(String(row.created_at));
      if (row.started_at !== null) decodeDateTime(String(row.started_at));
      if (row.completed_at !== null) decodeDateTime(String(row.completed_at));
      if (row.result_json !== null) JSON.parse(String(row.result_json));
    },
  );
}

function validateRows(
  table: string,
  rows: Array<Record<string, unknown>>,
  problems: string[],
  validate: (row: Record<string, unknown>) => void,
): void {
  for (const row of rows) {
    try {
      validate(row);
    } catch (error) {
      const reason = error instanceof Error ? error.message : 'unrecognised value';
      problems.push(`table "${table}" has an unreadable row (${reason})`);
      return;
    }
  }
}
