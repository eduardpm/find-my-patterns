import { encodeBool, encodeJson } from './codecs';
import type { DiaryDatabase } from './database';

/**
 * Seeds the fixed reference data, and **only when the tables are empty**.
 *
 * Against an existing diary this must be a complete no-op — FR-022. The seed order is meaningful: `GET /feelings` serves
 * feelings in this order and both clients render what they are given.
 */

const FEELINGS: Array<[string, string, string]> = [
  ['happy', 'Happy', 'positive'],
  ['excited', 'Excited', 'positive'],
  ['neutral', 'Neutral', 'neutral'],
  ['sleepy', 'Sleepy', 'negative'],
  ['exhausted', 'Exhausted', 'negative'],
  ['stressed', 'Stressed', 'negative'],
  ['sad', 'Sad', 'negative'],
  ['depressed', 'Depressed', 'negative'],
];

const GUIDING_QUESTIONS: Array<[string, string, string, string[], boolean]> = [
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
];

export function seed(db: DiaryDatabase): void {
  const hasFeelings = db.prepare<{ n: number }>('SELECT COUNT(*) AS n FROM feelings').get() as {
    n: number;
  };
  if (hasFeelings.n === 0) {
    const insert = db.prepare('INSERT INTO feelings ("key", label, valence) VALUES (?, ?, ?)');
    for (const [key, label, valence] of FEELINGS) insert.run(key, label, valence);
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
