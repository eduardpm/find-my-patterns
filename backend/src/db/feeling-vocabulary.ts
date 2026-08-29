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
 *  - **Valence lives on the feeling, not the group.** Most feelings simply inherit the group's
 *    valence — that is still what lets a client tint a whole group with one accent — but a feeling
 *    may declare its own and override it (#60: `calm`, `content`, `relaxed`, `focused` and
 *    `curious` are pleasant states that sit in the "Steady" group for presentation only). Grouping
 *    and labels never encode a claim about valence on their own; `FeelingSeed.valence` is the only
 *    thing insights, series and "when" ever read.
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
      // #60: these five are plainly pleasant states that happened to land in the "Steady" group
      // for presentation — grouping and labels are unchanged, but valence is a per-feeling fact,
      // not a group one, and scoring them 0 made them indistinguishable from `indifferent`.
      { key: 'calm', label: 'Calm', valence: 'positive' },
      { key: 'content', label: 'Content', valence: 'positive' },
      { key: 'relaxed', label: 'Relaxed', valence: 'positive' },
      { key: 'focused', label: 'Focused', valence: 'positive' },
      { key: 'curious', label: 'Curious', valence: 'positive' },
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
    // A feeling's own valence is authoritative when it states one (#60); the group's valence is
    // only the default every feeling started with. Grouping and labels are a presentation concern
    // and stay exactly as declared above — this is the one place valence is allowed to diverge
    // from the group it visually sits in.
    valence: 'valence' in feeling ? feeling.valence : group.valence,
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
