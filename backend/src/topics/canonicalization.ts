/**
 * The topic vocabulary, and the deterministic rules that decide which topic a phrase *is*.
 *
 * Pure and database-free on purpose. Two places produce topics — the keyword extractor in
 * `topics.service.ts` and the model in `inference/worker.ts` — and both have to reach the same
 * canonical name for the same words. When they do not, one idea lands in two rows and neither
 * crosses the minimum-occurrence threshold; that is exactly the fragmentation the audit found, and
 * the fix has to live where both callers can reach it without either importing the other.
 *
 * The model never decides equivalence here (A4-03, constitution Principle III). It proposes a
 * phrase; every rule below is arithmetic on words.
 *
 * Matching is on **whole words and phrases**, not raw substrings. Spec 002 FR-009 asks for
 * correlations between topics "mentioned in entry content", and a substring match is not a mention:
 * an earlier implementation matched `"ran"` inside `"drank"` and `"grandma"`, so *"I drank water"*
 * recorded the topic **exercise**. Every rule added since is held to the same standard.
 */

export const CURATED_TOPIC_KEYWORDS: Record<string, string[]> = {
  // Food, drink, and substances
  'coca cola': ['coca cola', 'coca-cola', 'coke', 'cola'],
  coffee: ['coffee', 'espresso', 'latte', 'cappuccino'],
  tea: ['tea'],
  'energy drinks': ['energy drink', 'energy drinks', 'red bull', 'monster energy'],
  hydration: ['water', 'hydration', 'hydrated', 'dehydrated'],
  alcohol: ['beer', 'wine', 'alcohol', 'cocktail'],
  smoking: ['smoke', 'smoked', 'smoking', 'cigarette', 'cigarettes', 'vape', 'vaping'],
  takeout: ['takeout', 'take-out', 'take out', 'fast food', 'delivery'],
  'junk food': ['pizza', 'chips', 'candy', 'chocolate', 'fries', 'junk food'],
  sugar: ['sugar', 'sugary', 'sweets', 'dessert', 'cake', 'cookies', 'ice cream'],
  'fruit and vegetables': ['fruit', 'fruits', 'vegetable', 'vegetables', 'salad'],
  'skipped meal': [
    'skipped breakfast',
    'skipped lunch',
    'skipped dinner',
    'skipped a meal',
    'empty stomach',
    'fasting',
  ],

  // Movement, routine, and restorative activities
  exercise: ['exercise', 'gym', 'workout', 'worked out', 'ran', 'running', 'yoga'],
  walking: ['walk', 'walked', 'walking', 'hike', 'hiked', 'hiking'],
  cycling: ['cycle', 'cycled', 'cycling', 'bike ride', 'biked', 'biking'],
  sedentary: ['sedentary', 'sitting all day', 'sat all day'],
  sleep: ['slept', 'sleep', 'nap', 'napped', 'insomnia', 'bedtime', 'woke up', 'poor sleep'],
  rest: ['rested', 'resting', 'downtime', 'took a break'],
  commute: ['commute', 'commuting', 'traffic', 'train ride', 'bus ride'],
  chores: ['chores', 'cleaned', 'cleaning', 'laundry', 'housework'],

  // Work and social setting. Keep specific relationships separate: "family" and "partner" can
  // have very different within-person associations even though both are broadly social time.
  work: [
    'work',
    'meeting',
    'meetings',
    'deadline',
    'overtime',
    'boss',
    // Added with A4: 'project review', 'project meeting' and 'review' were three separate
    // one-shot topic rows in real diaries, none of which ever reached three occurrences. They
    // are the same thing to the person writing them, and the canonical list is where that is
    // decided — not by asking the model whether two phrases mean the same (A4-03).
    'project',
    'projects',
    'review',
    'reviews',
    'presentation',
    'workload',
    'shift',
  ],
  study: ['school', 'class', 'studied', 'studying', 'homework', 'exam'],
  friends: ['friend', 'friends', 'hangout', 'hung out'],
  family: ['family', 'parent', 'parents', 'mother', 'father', 'sibling', 'siblings'],
  partner: ['partner', 'boyfriend', 'girlfriend', 'husband', 'wife', 'spouse'],
  colleagues: ['colleague', 'colleagues', 'coworker', 'coworkers', 'team-mate', 'teammate'],
  'time alone': ['alone', 'by myself', 'on my own', 'solitude'],
  'social event': ['party', 'social event', 'gathering', 'get-together'],
  conflict: ['argument', 'argued', 'fight', 'fought', 'conflict', 'disagreement'],

  // Body and health context
  hunger: ['hungry', 'hunger', 'starving'],
  pain: ['pain', 'painful', 'aching', 'sore'],
  headache: ['headache', 'headaches', 'migraine', 'migraines'],
  digestion: ['bloated', 'bloating', 'nausea', 'nauseous', 'indigestion', 'stomach ache'],
  illness: ['sick', 'ill', 'fever', 'have a cold', 'caught a cold', 'flu'],
  medication: ['medication', 'medicine', 'meds', 'prescription', 'painkiller'],
  'menstrual cycle': [
    'my period',
    'on my period',
    'got my period',
    'menstruation',
    'menstrual',
    'pms',
    'ovulation',
  ],

  // Environment, attention, and coping
  'screen time': ['phone', 'scrolling', 'social media', 'screen time'],
  outdoors: ['outside', 'outdoors', 'park', 'nature', 'forest', 'garden'],
  'sunny weather': ['sunny', 'sunshine', 'clear skies'],
  'rainy weather': ['rain', 'raining', 'rainy', 'storm', 'stormy'],
  'hot weather': ['heatwave', 'hot weather', 'too hot'],
  'cold weather': ['cold weather', 'freezing outside', 'too cold'],
  noise: ['noise', 'noisy', 'loud'],
  crowds: ['crowd', 'crowds', 'crowded'],
  travel: ['travel', 'travelled', 'traveled', 'trip', 'vacation', 'holiday'],
  music: ['music', 'playlist', 'concert', 'sang', 'singing'],
  reading: ['read a book', 'reading', 'book'],
  meditation: ['meditated', 'meditation', 'mindfulness', 'breathing exercise', 'deep breathing'],
  therapy: ['therapy', 'therapist', 'counselling', 'counseling'],
};

const escapeRegex = (value: string): string => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * Does `text` mention `phrase` as a whole word or phrase?
 *
 * `\b` at each end is what separates a mention from a coincidence: "ran" matches *"I ran home"* but
 * not *"I drank water"*. Multi-word variants ("coca cola", "worked out") and hyphenated ones
 * ("coca-cola") work unchanged, since the boundaries only apply at the ends.
 */
export function mentions(text: string, phrase: string): boolean {
  return new RegExp(`\\b${escapeRegex(phrase)}\\b`, 'i').test(text);
}

/** Pure, DB-free: which curated topics does this text actually mention? */
export function findCuratedMatches(textLower: string): Set<string> {
  const matches = new Set<string>();
  for (const [canonical, variants] of Object.entries(CURATED_TOPIC_KEYWORDS)) {
    if (variants.some((variant) => mentions(textLower, variant))) matches.add(canonical);
  }
  return matches;
}

// ---------------------------------------------------------------------------------------------
// Normalisation and canonical resolution (A4)
// ---------------------------------------------------------------------------------------------

/**
 * A4-01: the one normalisation every proposed topic passes through before anything looks at it.
 *
 * Lowercase, trimmed, punctuation stripped, whitespace collapsed. Nothing clever — the point is
 * that `"Project Review."`, `"project  review"` and `"project review"` are one string by the time
 * any rule sees them, so no later rule has to think about punctuation.
 */
export function normalizeTopicName(raw: string): string {
  return raw
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N} -]/gu, '')
    .replace(/[-\s]+/g, ' ')
    .trim();
}

/** Words that carry no topic meaning of their own. `fruit and vegetables` must not match on "and". */
export const TOPIC_STOPWORDS = new Set([
  'a',
  'an',
  'and',
  'at',
  'for',
  'from',
  'in',
  'is',
  'my',
  'of',
  'on',
  'or',
  'the',
  'to',
  'with',
]);

/**
 * A word reduced to the part inflection does not change.
 *
 * Deliberately crude — strip a plural or a participle ending and stop. A real stemmer would fold
 * "rest" into "restaurant" territory, and the whole reason topic matching is word-bounded is that
 * an over-eager match records a topic the entry never mentioned.
 */
export function stemToken(word: string): string {
  let current = word;
  // Applied until nothing more comes off, so "meetings" and "meeting" arrive at the same stem
  // rather than one stopping a step short of the other.
  for (let pass = 0; pass < 3; pass += 1) {
    const next = stripOneSuffix(current);
    if (next === current) break;
    current = next;
  }
  return current;
}

function stripOneSuffix(word: string): string {
  if (word.length <= 3) return word;
  if (word.endsWith('ies') && word.length >= 5) return `${word.slice(0, -3)}y`;
  if (word.endsWith('ing') && word.length - 3 >= 3) return word.slice(0, -3);
  if (word.endsWith('ed') && word.length - 2 >= 3) return word.slice(0, -2);
  // "es" comes off only after a sibilant — "classes" is "class", but "vegetables" is not
  // "vegetabl". Getting this backwards makes a word's singular and plural stem differently, which
  // is worse than not stemming at all: it splits one topic into two.
  if (word.endsWith('es') && /(s|x|z|ch|sh)es$/.test(word) && word.length - 2 >= 3) {
    return word.slice(0, -2);
  }
  // Never off a word that already ends in a double s or in "us" — "class" is not "clas" and
  // "focus" is not "focu".
  if (word.endsWith('s') && !/(ss|us)$/.test(word) && word.length - 1 >= 3) {
    return word.slice(0, -1);
  }
  return word;
}

/** The stems of a phrase's meaningful words, in order and de-duplicated. */
export function significantStems(name: string): string[] {
  return [
    ...new Set(
      normalizeTopicName(name)
        .split(' ')
        .filter((word) => word.length > 0 && !TOPIC_STOPWORDS.has(word))
        .map(stemToken),
    ),
  ];
}

const isSubsetOf = (a: string[], b: string[]): boolean =>
  a.length > 0 && a.every((token) => b.includes(token));

/** A topic row as the resolver needs to see it: its name and every alias pointing at it. */
export interface KnownTopic {
  name: string;
  aliases: string[];
}

/**
 * Which curated topic, if any, a phrase belongs to — and only one answer, always the same one.
 *
 * A phrase can legitimately hit two curated topics ("coffee and a walk"). The tie is broken by the
 * longest matched variant, then alphabetically, so the answer never depends on object key order.
 */
export function curatedTopicFor(normalized: string): string | null {
  let best: { canonical: string; length: number } | null = null;
  for (const [canonical, variants] of Object.entries(CURATED_TOPIC_KEYWORDS)) {
    for (const variant of variants) {
      if (!mentions(normalized, variant)) continue;
      if (
        best === null ||
        variant.length > best.length ||
        (variant.length === best.length && canonical < best.canonical)
      ) {
        best = { canonical, length: variant.length };
      }
    }
  }
  return best?.canonical ?? null;
}

/**
 * The canonical name a proposed topic should be stored under (A4-02).
 *
 * The rules are tried in order and the first that answers wins:
 *
 *  1. **the curated list** — the project's own vocabulary, and the only place a claim like
 *     "a project review is work" is allowed to be made;
 *  2. **an existing topic's name or alias**, matched exactly after normalisation — this is what
 *     makes a user-added alias take effect on the next recompute without the model running again
 *     (A4-04);
 *  3. **the same words wearing different endings** — "project meetings" is "project meeting";
 *  4. **one phrase's words inside another's** — "review" and "project review" are the same subject
 *     written at two lengths, and the shorter is kept as the canonical form.
 *
 * Returns `null` when nothing matches, and that is a deliberate outcome rather than a failure: a
 * genuinely novel topic is stored under its own normalised name (A4-10). This mapping is a
 * preference, never a filter.
 */
export function canonicalTopicName(proposal: string, known: KnownTopic[]): string | null {
  const normalized = normalizeTopicName(proposal);
  if (!normalized) return null;

  const curated = curatedTopicFor(normalized);
  if (curated) return curated;

  for (const topic of known) {
    if (normalizeTopicName(topic.name) === normalized) return topic.name;
    if (topic.aliases.some((alias) => normalizeTopicName(alias) === normalized)) return topic.name;
  }

  const proposedStems = significantStems(normalized);
  if (proposedStems.length === 0) return normalized;

  const serialized = proposedStems.join(' ');
  for (const topic of known) {
    const names = [topic.name, ...topic.aliases];
    if (names.some((name) => significantStems(name).join(' ') === serialized)) return topic.name;
  }

  // Sorted so the answer cannot depend on the order rows came back from the database.
  const candidates = [...known].sort((a, b) => a.name.localeCompare(b.name));
  for (const topic of candidates) {
    const topicStems = significantStems(topic.name);
    if (isSubsetOf(proposedStems, topicStems) || isSubsetOf(topicStems, proposedStems)) {
      // The shorter phrase is the canonical one: "review" says everything "project review" says
      // about its subject, and consolidating upward would bury the general topic under a specific
      // one that happened to be written first.
      return topicStems.length <= proposedStems.length ? topic.name : normalized;
    }
  }

  return normalized;
}
