import { encodeBool, encodeJson } from './codecs';
import type { DiaryDatabase } from './database';
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
    'Since your last entry—or in the last few hours—what happened? What were you doing, where were you, and who was around?',
    [],
    true,
  ],
  [
    'mind_body',
    'mind_body',
    'What did you notice in your mind and body? Include thoughts, energy, tension, hunger, pain, or other sensations.',
    [],
    true,
  ],
  [
    'small_influences',
    'small_influences',
    'What small things might have influenced you—even if they seem unimportant? Think sleep, food or drink, caffeine or alcohol, medication, movement, work, social contact, screen time, weather, or a change in routine.',
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
