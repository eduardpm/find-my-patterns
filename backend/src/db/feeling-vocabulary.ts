/**
 * The feeling vocabulary, as one nested list.
 *
 * This file is the single definition of both levels — the handful of groups a user picks from
 * first, and the granular feelings inside each one. Constitution Principle VII puts the feeling
 * set in the backend, and having *one* place for it here means the seed, the migration, the
 * request validator and the model's structured-output schema cannot drift apart: each derives
 * from this array rather than restating it.
 *
 * Two invariants the rest of the code relies on:
 *
 *  - **Every feeling in a group shares that group's valence.** Valence is a rule — it decides an
 *    insight's keep/change direction — so it stays on the individual feeling row where it always
 *    was. Keeping a group internally consistent is what lets a client tint a whole group with one
 *    accent without ever claiming something the backend did not say.
 *  - **The eight original keys still exist, unrenamed.** `happy`, `excited`, `neutral`, `sleepy`,
 *    `exhausted`, `stressed`, `sad` and `depressed` are foreign keys in every existing diary. They
 *    are re-homed into groups, never replaced.
 *
 * Order is meaningful and served as-is: `GET /feelings` emits groups and their feelings in exactly
 * this order, and both clients render what they are given.
 */

export type SeedValence = 'positive' | 'neutral' | 'negative';

const GROUPS = [
  {
    key: 'uplifted',
    label: 'Uplifted',
    valence: 'positive',
    feelings: [
      { key: 'happy', label: 'Happy' },
      { key: 'excited', label: 'Excited' },
      { key: 'grateful', label: 'Grateful' },
      { key: 'proud', label: 'Proud' },
      { key: 'hopeful', label: 'Hopeful' },
      { key: 'energised', label: 'Energised' },
      { key: 'affectionate', label: 'Affectionate' },
      { key: 'playful', label: 'Playful' },
    ],
  },
  {
    key: 'steady',
    label: 'Steady',
    valence: 'neutral',
    feelings: [
      { key: 'neutral', label: 'Neutral' },
      { key: 'calm', label: 'Calm' },
      { key: 'content', label: 'Content' },
      { key: 'relaxed', label: 'Relaxed' },
      { key: 'focused', label: 'Focused' },
      { key: 'curious', label: 'Curious' },
      { key: 'indifferent', label: 'Indifferent' },
    ],
  },
  {
    key: 'tense',
    label: 'Tense',
    valence: 'negative',
    feelings: [
      { key: 'stressed', label: 'Stressed' },
      { key: 'anxious', label: 'Anxious' },
      { key: 'overwhelmed', label: 'Overwhelmed' },
      { key: 'frustrated', label: 'Frustrated' },
      { key: 'irritable', label: 'Irritable' },
      { key: 'angry', label: 'Angry' },
      { key: 'restless', label: 'Restless' },
      { key: 'guilty', label: 'Guilty' },
    ],
  },
  {
    key: 'low',
    label: 'Low',
    valence: 'negative',
    feelings: [
      { key: 'sad', label: 'Sad' },
      { key: 'depressed', label: 'Depressed' },
      { key: 'lonely', label: 'Lonely' },
      { key: 'disappointed', label: 'Disappointed' },
      { key: 'hopeless', label: 'Hopeless' },
      { key: 'numb', label: 'Numb' },
      { key: 'sleepy', label: 'Sleepy' },
      { key: 'exhausted', label: 'Exhausted' },
    ],
  },
] as const;

export type FeelingGroupKey = (typeof GROUPS)[number]['key'];
export type FeelingKey = (typeof GROUPS)[number]['feelings'][number]['key'];

export interface FeelingGroupSeed {
  key: FeelingGroupKey;
  label: string;
  valence: SeedValence;
  sortOrder: number;
}

export interface FeelingSeed {
  key: FeelingKey;
  label: string;
  valence: SeedValence;
  groupKey: FeelingGroupKey;
  sortOrder: number;
}

export const FEELING_GROUP_SEED: FeelingGroupSeed[] = GROUPS.map((group, index) => ({
  key: group.key,
  label: group.label,
  valence: group.valence,
  sortOrder: index,
}));

/** Flattened in group order, then in each group's own order — the order clients receive. */
export const FEELING_SEED: FeelingSeed[] = GROUPS.flatMap((group, groupIndex) =>
  group.feelings.map((feeling, feelingIndex) => ({
    key: feeling.key,
    label: feeling.label,
    valence: group.valence,
    groupKey: group.key,
    // Leaves room to insert a feeling inside a group later without renumbering the ones after it.
    sortOrder: groupIndex * 100 + feelingIndex,
  })),
);

/**
 * The vocabulary as Zod/JSON-Schema enum tuples. Non-empty by construction, but neither `flatMap`
 * nor `map` can prove that to the type system, hence the assertions.
 */
export const FEELING_KEYS = FEELING_SEED.map((feeling) => feeling.key) as [
  FeelingKey,
  ...FeelingKey[],
];

export const FEELING_GROUP_KEYS = FEELING_GROUP_SEED.map((group) => group.key) as [
  FeelingGroupKey,
  ...FeelingGroupKey[],
];

/** Which group a feeling belongs to, for validating what the model proposed. */
export const GROUP_BY_FEELING_KEY: Record<string, FeelingGroupKey> = Object.fromEntries(
  FEELING_SEED.map((feeling) => [feeling.key, feeling.groupKey]),
);

/**
 * The ceiling on how many feelings one entry may carry — the analyser's and the user's alike.
 *
 * Four rather than unbounded. An entry that is genuinely four different feelings is rare; a model
 * asked for "every feeling here" reliably returns a shopping list, and every extra feeling is
 * another `(topic, feeling)` pair diluting pattern detection with occurrences the user never
 * actually felt strongly. Holding the user to the same ceiling keeps the two ends symmetrical.
 */
export const MAX_FEELINGS_PER_ENTRY = 4;
