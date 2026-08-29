import { randomUUID } from 'node:crypto';
import { loadConfig } from '../config';
import { encodeBool, encodeDate, encodeDateTime, encodeJson, nowUtc, todayLocal } from './codecs';
import { openDiary, type DiaryDatabase } from './database';
import { FEELING_GROUP_SEED, FEELING_SEED } from './feeling-vocabulary';

/**
 * Seeds the fixed reference data, and **only when the tables are empty**.
 *
 * Against an existing diary this must be a complete no-op — FR-022. Growing the vocabulary of an
 * existing diary is therefore not this function's job; that is `npm run migrate-db`, which the
 * user runs deliberately (see `migrate.ts`).
 *
 * The seed order is meaningful: `GET /feelings` serves groups and feelings in `sort_order`, which
 * is assigned from the order in `feeling-vocabulary.ts`, and both clients render what they are
 * given.
 */

/**
 * The question library.
 *
 * Exported because `migrate.ts` inserts the ones an older diary is missing. `seed()` itself still
 * refuses to touch a non-empty table (FR-022), so growing an existing diary stays the deliberate
 * act the user performs, never a side effect of starting the server.
 */
export const GUIDING_QUESTIONS: Array<[string, string, string, string[], boolean]> = [
  [
    'general_feeling',
    'general',
    'What happened since your last entry — and who was around?',
    [],
    true,
  ],
  ['mind_body', 'mind_body', 'What did you notice in your mind and body?', [], true],
  [
    'small_influences',
    'small_influences',
    'Anything small that might have influenced you? (sleep, food, movement…)',
    [],
    true,
  ],
  [
    'response_outcome',
    'response_outcome',
    'What did you do next, and what changed afterward?',
    [
      'stressed',
      'sad',
      'depressed',
      'anxious',
      'angry',
      'upset',
      'overwhelmed',
      'exhausted',
      'tired',
      'sleepy',
      'pain',
      'headache',
      'argument',
      'conflict',
      'cried',
      'panic',
      'frustrated',
      'difficult',
      'rough',
      'awful',
      'terrible',
      'happy',
      'excited',
      'proud',
      'great',
    ],
    false,
  ],

  // ---------------------------------------------------------------------------------------------
  // Time-of-day prompts (A6).
  //
  // These are what make the day genuinely segmented rather than merely described as segmented: an
  // entry answered through one of them carries the slot it belongs to, which is what temporal
  // precedence needs in order to order two entries from the same day. All three are optional — the
  // mandatory general prompt is unchanged (FR-004/FR-005, A6-03) — and none carries a trigger
  // keyword, because they are offered by the clock rather than by what the user just wrote.
  // ---------------------------------------------------------------------------------------------
  [
    'morning_start',
    'morning',
    'How did the morning start? Think waking up, sleep, the first hour, and anything you took or skipped before the day began.',
    [],
    false,
  ],
  [
    'afternoon_middle',
    'afternoon',
    'How has the middle of the day gone? Think work or study, food, movement, and who you have been around since this morning.',
    [],
    false,
  ],
  [
    'evening_close',
    'evening',
    'How is the day ending? Think what changed since this afternoon, what you did to wind down, and what you are carrying into tonight.',
    [],
    false,
  ],
];

export function seed(db: DiaryDatabase): void {
  const hasGroups = db.prepare<{ n: number }>('SELECT COUNT(*) AS n FROM feeling_groups').get() as {
    n: number;
  };
  if (hasGroups.n === 0) {
    const insert = db.prepare(
      'INSERT INTO feeling_groups ("key", label, valence, sort_order) VALUES (?, ?, ?, ?)',
    );
    for (const group of FEELING_GROUP_SEED) {
      insert.run(group.key, group.label, group.valence, group.sortOrder);
    }
  }

  const hasFeelings = db.prepare<{ n: number }>('SELECT COUNT(*) AS n FROM feelings').get() as {
    n: number;
  };
  if (hasFeelings.n === 0) {
    const insert = db.prepare(
      'INSERT INTO feelings ("key", label, valence, group_key, sort_order) VALUES (?, ?, ?, ?, ?)',
    );
    for (const feeling of FEELING_SEED) {
      insert.run(feeling.key, feeling.label, feeling.valence, feeling.groupKey, feeling.sortOrder);
    }
  }

  const hasQuestions = db
    .prepare<{ n: number }>('SELECT COUNT(*) AS n FROM guiding_questions')
    .get() as { n: number };
  if (hasQuestions.n === 0) {
    const insert = db.prepare(
      'INSERT INTO guiding_questions ("key", category, prompt_text, trigger_keywords, is_mandatory) VALUES (?, ?, ?, ?, ?)',
    );
    for (const [key, category, prompt, keywords, mandatory] of GUIDING_QUESTIONS) {
      insert.run(key, category, prompt, encodeJson(keywords), encodeBool(mandatory));
    }
  }
}

/**
 * One mixed-valence example entry, with plausible suggested topic↔feeling pairings (E-1a) — the
 * exact shape the pairing feature exists for: one part of the day was hard, another part was
 * good, and a client building the confirm-pairing screen needs a real entry to develop against
 * rather than an empty diary.
 *
 * **Deliberately not called by {@link seed}.** `seed()` runs on *every* server boot
 * (`db/database.provider.ts`) and must leave a populated diary — or a freshly created empty one —
 * exactly as the person left it (FR-022); writing a diary entry nobody wrote into every fresh
 * diary a real user creates would be precisely the kind of silent surprise FR-022 exists to
 * prevent. This is invoked explicitly and only: `npm run seed-example-data -- <path-to-a-scratch-diary>`.
 */
export function seedExampleMixedValenceEntry(db: DiaryDatabase): { entryId: string } {
  const now = encodeDateTime(nowUtc());
  const entryId = randomUUID();
  const rawText =
    'Missed my workout again, which was disappointing — I keep meaning to go and then just do ' +
    'not. But I called my family in the evening and that felt really warm; it was good to hear ' +
    'their voices.';

  db.transaction(() => {
    db.prepare(
      `INSERT INTO diary_entries
       (id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source, version)
       VALUES (?, ?, ?, ?, 'freeform', ?, 'disappointed', 'suggested', 1)`,
    ).run(entryId, now, now, encodeDate(todayLocal()), rawText);

    const insertFeeling = db.prepare(
      'INSERT INTO entry_feelings (entry_id, feeling_key, position) VALUES (?, ?, ?)',
    );
    insertFeeling.run(entryId, 'disappointed', 0);
    insertFeeling.run(entryId, 'grateful', 1);

    const findTopic = db.prepare('SELECT id FROM topics WHERE name = ?');
    const insertTopic = db.prepare(
      `INSERT INTO topics (id, name, aliases, first_seen_at, last_seen_at) VALUES (?, ?, ?, ?, ?)`,
    );
    const linkTopic = db.prepare(
      `INSERT OR IGNORE INTO entry_topics (entry_id, topic_id, extracted_by) VALUES (?, ?, 'llm')`,
    );
    const insertPairing = db.prepare(
      `INSERT INTO entry_topic_feelings (entry_id, topic_id, feeling_key, source)
       VALUES (?, ?, ?, 'suggested')`,
    );

    const topicIds: Record<string, string> = {};
    for (const name of ['exercise', 'family']) {
      const existing = findTopic.get(name) as { id: string } | undefined;
      const topicId = existing?.id ?? randomUUID();
      if (!existing) insertTopic.run(topicId, name, encodeJson([]), now, now);
      linkTopic.run(entryId, topicId);
      topicIds[name] = topicId;
    }

    insertPairing.run(entryId, topicIds.exercise, 'disappointed');
    insertPairing.run(entryId, topicIds.family, 'grateful');
  });

  return { entryId };
}

if (require.main === module) {
  const target = process.argv[2] ?? loadConfig().databasePath;
  try {
    const db = openDiary(target);
    const { entryId } = seedExampleMixedValenceEntry(db);
    db.close();
    console.log(`Seeded one mixed-valence example entry (${entryId}) into ${target}`);
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}
