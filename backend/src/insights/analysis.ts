/**
 * The arithmetic behind every claim the Insights view makes — pure, database-free, LLM-free.
 *
 * Everything in this file is a function of counts. That is the point: the constitution's
 * "Deterministic Core, LLM at the Edges" says a number the user is shown must be reproducible from
 * their own diary, so the counting, the lift, the collinearity split and the sentence that states
 * them are all written here and unit-tested in isolation. `patterns.service.ts` supplies the rows
 * and stores the result; it decides nothing.
 *
 * Three rules run through the whole file and are worth stating once:
 *
 *  - **A number is never invented to fill a gap.** Where a rate cannot be computed — no comparison
 *    group, no evidence in the window — the result carries a reason code and no lift, and the
 *    sentence says so in words (A3-02).
 *  - **Association, never causation.** Every sentence generated here says "with" and "without",
 *    never "because" or "protects" (A3-08 / I1-07).
 *  - **Ties break deterministically**, because two clients sorting the same list differently is
 *    the same defect as showing different numbers (C-02).
 */

import type { NaiveDateTime, PlainDate } from '../db/codecs';
import {
  COLLINEARITY_THRESHOLD,
  HOUR_BLOCKS,
  MAX_INTENSITY,
  MIN_COMPARISON_ENTRIES,
  MIN_CONFOUNDER_CO_OCCURRENCES,
  MIN_LIFT,
  RECENCY_WINDOW_DAYS,
  SEASONS,
  STRONG_LIFT,
  STRONG_MIN_OCCURRENCES,
  TIME_OF_DAY_BUCKETS,
  VALENCE_SCORE,
  WEEKDAYS,
  WEEKEND_START_INDEX,
  type DayTypeKey,
  type HourBlockKey,
  type SeasonKey,
  type TimeOfDayKey,
} from './constants';

// ---------------------------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------------------------

/**
 * Days between two calendar dates, as whole days.
 *
 * Computed through `Date.UTC` rather than by subtracting local `Date`s: a diary spanning a
 * daylight-saving boundary would otherwise produce a 30-day window that is 29 days and 23 hours
 * long, and the entry on the boundary would drop in and out of the window twice a year.
 */
export function daysBetween(from: PlainDate, to: PlainDate): number {
  const a = Date.UTC(from.year, from.month - 1, from.day);
  const b = Date.UTC(to.year, to.month - 1, to.day);
  return Math.round((b - a) / 86_400_000);
}

/** Inclusive of both ends: with a 30-day window, an entry 29 days old is in and 30 days old is out. */
export function withinWindow(
  entryDate: PlainDate,
  today: PlainDate,
  windowDays: number = RECENCY_WINDOW_DAYS,
): boolean {
  const age = daysBetween(entryDate, today);
  return age >= 0 && age < windowDays;
}

/** Monday-first index, matching `WEEKDAYS`. `Date.getUTCDay()` is Sunday-first, so it is rotated. */
export function weekdayIndex(date: PlainDate): number {
  const day = new Date(Date.UTC(date.year, date.month - 1, date.day)).getUTCDay();
  return (day + 6) % 7;
}

/** A calendar date shifted by `days` (negative to go back), through `Date.UTC` for the same reason `daysBetween` is. */
export function addDays(date: PlainDate, days: number): PlainDate {
  const shifted = new Date(Date.UTC(date.year, date.month - 1, date.day) + days * 86_400_000);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}

/** The Monday that starts `date`'s week (CH-0) — matches `weekdayIndex`'s Monday-first convention. */
export function weekStart(date: PlainDate): PlainDate {
  return addDays(date, -weekdayIndex(date));
}

/** The first of `date`'s month (CH-0). */
export function monthStart(date: PlainDate): PlainDate {
  return { year: date.year, month: date.month, day: 1 };
}

/**
 * Which part of the day an entry was written in (I5-01).
 *
 * The evening bucket wraps past midnight, so a 01:30 entry is filed under the evening it belongs
 * to rather than opening a fourth bucket nobody would recognise.
 */
export function timeOfDayBucket(createdAt: NaiveDateTime): TimeOfDayKey {
  const hour = createdAt.hour;
  for (const bucket of TIME_OF_DAY_BUCKETS) {
    if (bucket.startHour < bucket.endHour) {
      if (hour >= bucket.startHour && hour < bucket.endHour) return bucket.key;
    } else if (hour >= bucket.startHour || hour < bucket.endHour) {
      return bucket.key;
    }
  }
  return 'evening';
}

/**
 * Which of `HOUR_BLOCKS`' twelve 2-hour blocks an entry's `created_at` falls into (CH-5).
 *
 * Unlike `timeOfDayBucket`, every block is the same fixed width and none of them wraps past
 * midnight, so this is a plain division rather than a wrap-aware scan: hour 23 is still `Math.floor`
 * away from a 24th block that does not exist, hence the clamp.
 */
export function hourBlockKey(createdAt: NaiveDateTime): HourBlockKey {
  const index = Math.min(Math.floor(createdAt.hour / 2), HOUR_BLOCKS.length - 1);
  return HOUR_BLOCKS[index].key;
}

/** Saturday and Sunday only (#21) — `weekdayIndex` is Monday-first, so those are indices 5 and 6. */
export function dayTypeFor(date: PlainDate): DayTypeKey {
  return weekdayIndex(date) >= WEEKEND_START_INDEX ? 'weekend' : 'weekday';
}

/** Meteorological season from the calendar month alone (#21) — see `SEASONS` for why not the equinox. */
export function seasonFor(date: PlainDate): SeasonKey {
  const season = SEASONS.find((candidate) =>
    (candidate.months as readonly number[]).includes(date.month),
  );
  // Every month is covered by exactly one entry in SEASONS; this is unreachable, not a real fallback.
  return season ? season.key : 'winter';
}

/**
 * The four passive context factors an entry carries (#21) — derived once, here, from `entry_date`
 * and `created_at` alone, so `patterns.service.ts` and any future caller read the same four keys
 * rather than each deriving their own. No schema change and nothing stored: this runs fresh on every
 * `GET /insights`, exactly like the topic association it feeds into.
 *
 * Always exactly one key per category (`weekday:`, `daytype:`, `timeofday:`, `season:`) — the
 * "never pair context factors with each other" rule in `patterns.service.ts#contextPatterns` depends
 * on this list never containing two keys from the same category for one entry.
 */
export function contextFactorsForEntry(entryDate: PlainDate, createdAt: NaiveDateTime): string[] {
  return [
    `weekday:${WEEKDAYS[weekdayIndex(entryDate)].key}`,
    `daytype:${dayTypeFor(entryDate)}`,
    `timeofday:${timeOfDayBucket(createdAt)}`,
    `season:${seasonFor(entryDate)}`,
  ];
}

// ---------------------------------------------------------------------------------------------
// Lift
// ---------------------------------------------------------------------------------------------

/**
 * Why a lift could not be computed. Never a free-text string: both clients switch on these, and a
 * sentence they had to parse would be a rule leaking out of the backend.
 */
export type ComparisonReason =
  'insufficient_comparison' | 'no_absent_occurrences' | 'no_window_evidence';

/** The 2×2 table a pattern's strength is read off, plus what could be concluded from it. */
export interface Association {
  /** Entries with the topic **and** the feeling. */
  presentCount: number;
  /** Entries with the topic. */
  presentTotal: number;
  /** Entries without the topic but with the feeling. */
  absentCount: number;
  /** Entries without the topic. */
  absentTotal: number;
  presentRate: number | null;
  absentRate: number | null;
  /** How much likelier the feeling is with the topic than without it, or `null` with a reason. */
  lift: number | null;
  comparisonReason: ComparisonReason | null;
}

/**
 * Build the association from the four raw counts.
 *
 * The three `null` cases are the whole reason this returns a reason code rather than a number:
 *
 *  - **no evidence in the window** — the pair is historical, so there is nothing recent to divide;
 *  - **too small a comparison group** — one entry would swing the "without" rate by 50 points;
 *  - **the feeling never occurs without the topic** — a real and strong finding, but the ratio is
 *    a division by zero, and reporting infinity as "6.2×" would be a fabricated number (A3-02).
 */
export function associationFrom(
  presentCount: number,
  presentTotal: number,
  absentCount: number,
  absentTotal: number,
): Association {
  const presentRate = presentTotal > 0 ? presentCount / presentTotal : null;
  const absentRate = absentTotal > 0 ? absentCount / absentTotal : null;

  let comparisonReason: ComparisonReason | null = null;
  let lift: number | null = null;

  if (presentTotal === 0) {
    comparisonReason = 'no_window_evidence';
  } else if (absentTotal < MIN_COMPARISON_ENTRIES) {
    comparisonReason = 'insufficient_comparison';
  } else if (absentCount === 0) {
    comparisonReason = 'no_absent_occurrences';
  } else {
    lift = presentRate! / absentRate!;
  }

  return {
    presentCount,
    presentTotal,
    absentCount,
    absentTotal,
    presentRate,
    absentRate,
    lift,
    comparisonReason,
  };
}

/**
 * A3-04: suppressed only on a lift that was actually computed.
 *
 * An un-computable lift is not a weak one. Suppressing on `null` would delete exactly the pairs
 * with no counter-examples — the strongest evidence in the diary — for having too clean a table.
 */
export function suppressedByLift(association: Association, minLift: number = MIN_LIFT): boolean {
  return association.lift !== null && association.lift < minLift;
}

/** A3-07 — both conditions, so a 4× lift over three entries is not dressed up as a finding. */
export function isStrong(association: Association, occurrenceCount: number): boolean {
  return (
    association.lift !== null &&
    association.lift >= STRONG_LIFT &&
    occurrenceCount >= STRONG_MIN_OCCURRENCES
  );
}

/** The inverse view of the same table: the feeling seen against the topic's *absence* (I1-01). */
export function invert(association: Association): Association {
  return associationFrom(
    association.absentCount,
    association.absentTotal,
    association.presentCount,
    association.presentTotal,
  );
}

// ---------------------------------------------------------------------------------------------
// Mixed-valence pairing (E-1b)
// ---------------------------------------------------------------------------------------------

/**
 * Whether an entry's own feelings span both valence signs — the trigger for the pairing rule
 * (§11.7 engine rule #4). Only a positive feeling alongside a negative one makes an entry mixed;
 * everything else, including a diary with only one feeling, is single-valence and untouched by
 * the pairing rule (rule #1).
 *
 * Neutral counts as its own sign, never as a wildcard that could tip a mix either way: positive +
 * neutral is not mixed, negative + neutral is not mixed, and neutral + neutral is not mixed. Only
 * `positive` and `negative` — together, in any company — produce a mixed entry. A key this
 * function has no valence for is skipped rather than guessed at, the same defensive posture
 * `averageValence` takes with a score it cannot find.
 */
export function isMixedValence(
  feelingKeys: string[],
  valenceOf: (feelingKey: string) => string | undefined,
): boolean {
  let hasPositive = false;
  let hasNegative = false;
  for (const feelingKey of feelingKeys) {
    const valence = valenceOf(feelingKey);
    if (valence === 'positive') hasPositive = true;
    else if (valence === 'negative') hasNegative = true;
  }
  return hasPositive && hasNegative;
}

/**
 * Rule 2/3 of the pairing rule above, as a standalone predicate (#37, L-2).
 *
 * `PatternsService#buildCandidates` had this as a private closure over its own per-entry maps —
 * correct, but not callable from anywhere counting occurrences for less than the whole diary. The
 * insight progress surface (`progress.service.ts`) needs the exact same yes/no for one entry at a
 * time — a near-threshold count that disagreed with what a future recompute would actually count
 * would be the dishonesty this product's whole "counts only" premise exists to rule out — so the
 * predicate is extracted here, pure and entry-shape-agnostic, and both call sites now share it
 * rather than keeping two hand-written copies of one rule in sync by hand.
 *
 * An entry is excluded from one specific `(topicId, feelingKey)` pair's count exactly when it is
 * mixed-valence *and* that exact pair is not among its own confirmed pairings. Single-valence
 * entries (`isMixed === false`) are never excluded from anything, whatever `confirmedPairs` holds.
 */
export function isPairExcluded(
  isMixed: boolean,
  confirmedPairs: ReadonlySet<string>,
  topicId: string,
  feelingKey: string,
): boolean {
  return isMixed && !confirmedPairs.has(`${topicId} ${feelingKey}`);
}

// ---------------------------------------------------------------------------------------------
// Sentences
// ---------------------------------------------------------------------------------------------

/** Percentages are whole numbers everywhere, so the same rate never reads two ways. */
export function percent(rate: number): number {
  return Math.round(rate * 100);
}

const plural = (count: number, one: string, many: string): string => (count === 1 ? one : many);

/**
 * The observation, stated with the numbers that produced it (A3-06, C-05).
 *
 * "in the last 30 days" is generated from the same window the counting used, so the sentence
 * cannot drift from the number the way "recent" over a lifetime count did (I3-04). No model is
 * allowed near this string: a fluent paraphrase that said "several" instead of "8" would read
 * better and be worth less.
 */
export function forwardNarrative(
  feelingLabel: string,
  topic: string,
  association: Association,
  windowDays: number = RECENCY_WINDOW_DAYS,
): string {
  const head =
    `You felt ${feelingLabel} in ${association.presentCount} of ${association.presentTotal} ` +
    `${plural(association.presentTotal, 'entry', 'entries')} mentioning ${topic} in the last ` +
    `${windowDays} days (${percent(association.presentRate ?? 0)}%)`;

  switch (association.comparisonReason) {
    case 'no_window_evidence':
      return `You have no entries mentioning ${topic} in the last ${windowDays} days.`;
    case 'insufficient_comparison':
      return `${head}. There are not enough entries without ${topic} to compare.`;
    case 'no_absent_occurrences':
      return (
        `${head}, and in none of the ${association.absentTotal} ` +
        `${plural(association.absentTotal, 'entry', 'entries')} without it.`
      );
    default:
      return (
        `${head}, and in ${association.absentCount} of ${association.absentTotal} ` +
        `${plural(association.absentTotal, 'entry', 'entries')} without it ` +
        `(${percent(association.absentRate ?? 0)}%).`
      );
  }
}

/**
 * The inverse card's sentence (I1-04).
 *
 * Phrased as "less", never as "protects you from" — the diary shows an association between the
 * topic's absence and the feeling, and nothing in it supports a claim about protection (I1-07).
 */
export function inverseNarrative(
  feelingLabel: string,
  topic: string,
  /** The inverse association: "present" is the topic's *absence*. */
  association: Association,
  windowDays: number = RECENCY_WINDOW_DAYS,
): string {
  const head =
    `You felt ${feelingLabel} in ${association.presentCount} of ${association.presentTotal} ` +
    `${plural(association.presentTotal, 'entry', 'entries')} without ${topic} in the last ` +
    `${windowDays} days (${percent(association.presentRate ?? 0)}%)`;

  switch (association.comparisonReason) {
    case 'no_window_evidence':
      return `You have no entries without ${topic} in the last ${windowDays} days.`;
    case 'insufficient_comparison':
      return `${head}. There are not enough entries mentioning ${topic} to compare.`;
    case 'no_absent_occurrences':
      return (
        `${head}, and in none of the ${association.absentTotal} ` +
        `${plural(association.absentTotal, 'entry', 'entries')} that mention it.`
      );
    default:
      return (
        `${head}, and in ${association.absentCount} of ${association.absentTotal} ` +
        `${plural(association.absentTotal, 'entry', 'entries')} that mention it ` +
        `(${percent(association.absentRate ?? 0)}%).`
      );
  }
}

/**
 * The context card's sentence (#21) — the same shape as `forwardNarrative`, with the topic's
 * "mentioning X" swapped for a context factor's phrase ("on Sundays", "in the evening", …), because
 * "mentioning on Sundays" is not English. The branching on `comparisonReason` is identical on
 * purpose: this is the same 2×2 table, read the same way, about a different kind of "present".
 */
export function contextNarrative(
  feelingLabel: string,
  factorPhrase: string,
  association: Association,
  windowDays: number = RECENCY_WINDOW_DAYS,
): string {
  const head =
    `You felt ${feelingLabel} in ${association.presentCount} of ${association.presentTotal} ` +
    `${plural(association.presentTotal, 'entry', 'entries')} ${factorPhrase} in the last ` +
    `${windowDays} days (${percent(association.presentRate ?? 0)}%)`;

  switch (association.comparisonReason) {
    case 'no_window_evidence':
      return `You have no entries ${factorPhrase} in the last ${windowDays} days.`;
    case 'insufficient_comparison':
      return `${head}. There are not enough other entries to compare.`;
    case 'no_absent_occurrences':
      return (
        `${head}, and in none of the other ${association.absentTotal} ` +
        `${plural(association.absentTotal, 'entry', 'entries')}.`
      );
    default:
      return (
        `${head}, and in ${association.absentCount} of ${association.absentTotal} other ` +
        `${plural(association.absentTotal, 'entry', 'entries')} ` +
        `(${percent(association.absentRate ?? 0)}%).`
      );
  }
}

/** A historical pattern's footnote (I3-07): how long ago, and how much there is in total. */
export function historicalNote(lifetimeCount: number, daysSinceLastOccurrence: number): string {
  const ago =
    daysSinceLastOccurrence <= 0
      ? 'today'
      : `${daysSinceLastOccurrence} ${plural(daysSinceLastOccurrence, 'day', 'days')} ago`;
  return (
    `Last seen ${ago}. ${lifetimeCount} ${plural(lifetimeCount, 'occurrence', 'occurrences')} ` +
    `across your whole diary.`
  );
}

/** The bland advice a pattern always carries, before the model has had a look at it. */
export function templateSuggestionFor(feelingLabel: string, topic: string): string {
  return `Pay attention to how ${topic} affects your ${feelingLabel} feeling.`;
}

// ---------------------------------------------------------------------------------------------
// "Worth trying" recommendations (R-1)
// ---------------------------------------------------------------------------------------------

/**
 * R-1's card sentence, for a pattern whose badge already reads `'keep'` (`badgeDirectionFor` in
 * `patterns.service.ts`) — the topic is either protective (an inverse pattern, negative feeling: the
 * bad feeling is likelier *without* the topic) or worth continuing (a forward pattern, positive
 * feeling: the good feeling is likelier *with* it).
 *
 * `lift` is a required `number`, not `number | null`, on purpose — a `'keep'` badge is only ever
 * given for a lift `badgeDirectionFor` already confirmed is defined and at or above `MIN_LIFT`
 * (P0-6). There is deliberately no branch here for a missing one: a caller holding a null lift has
 * no business calling this function, and threading a `comparisonReason` switch through it the way
 * `forwardNarrative`/`inverseNarrative` do for their own, wider range of inputs would just be dead
 * code that could never run.
 *
 * Every number in the sentence is one the pattern's own card already shows (`present_count`,
 * `present_total`, `absent_count`, `absent_total`, `lift`) — R-0's "cites the user's own entries" —
 * and the copy states an association only, never a cause: "may help" for the inverse case, never
 * "will fix" or "protects you from" (I1-07 makes the same call for the inverse card's own
 * narrative). The sentence is composed here, in full, because `mobile/CLAUDE.md`'s one rule is that
 * the backend owns the wording; a client that built this prose from `action_topic` alone would be
 * doing the one thing that rule forbids.
 */
export function recommendationSentenceFor(
  kind: 'forward' | 'inverse',
  feelingLabel: string,
  topic: string,
  lift: number,
  presentCount: number,
  presentTotal: number,
  absentCount: number,
  absentTotal: number,
): string {
  const liftText = `${lift.toFixed(1)}×`;
  if (kind === 'inverse') {
    return (
      `On days without ${topic}, ${feelingLabel} is ${liftText} more likely ` +
      `(${presentCount} of ${presentTotal} without vs ${absentCount} of ${absentTotal} with). ` +
      `More ${topic} days may help — here's the evidence.`
    );
  }
  return (
    `On days with ${topic}, ${feelingLabel} is ${liftText} more likely ` +
    `(${presentCount} of ${presentTotal} with vs ${absentCount} of ${absentTotal} without). ` +
    `Keep doing ${topic} — here's the evidence.`
  );
}

/**
 * R-1's card headline — the action, not the evidence (`recommendationSentenceFor` states that). Two
 * phrasings, matching the two kinds `badgeDirectionFor` can call `'keep'` for: more of a protective
 * absence (inverse), or continuing what the diary already shows works (forward). Sent as its own
 * field rather than left for the client to build from `action_topic` — see
 * `recommendationSentenceFor`'s doc comment for why that line is not the client's to cross.
 */
export function recommendationHeadlineFor(kind: 'forward' | 'inverse', topic: string): string {
  return kind === 'inverse' ? `More ${topic} days` : `Keep doing ${topic}`;
}

// ---------------------------------------------------------------------------------------------
// Confounders (I2)
// ---------------------------------------------------------------------------------------------

export interface ConfounderSplit {
  /** The other topic X keeps company with. */
  topic: string;
  /** Share of X's entries that also contain Y. */
  coOccurrenceRate: number;
  bothCount: number;
  onlyThisCount: number;
  onlyOtherCount: number;
  neitherCount: number;
  /** True when no entry separates the two, so nothing can be concluded about which one matters. */
  inseparable: boolean;
  note: string;
}

/**
 * Does a second topic travel closely enough with the first to muddy its pattern?
 *
 * The four cells are all returned, not just the rate, because the rate alone hides the case that
 * decides whether the warning means anything: with `onlyThisCount === 0` the diary contains no
 * entry that could tell the two apart, and saying "could really be about Y" would imply a
 * comparison that was never made (I2-04).
 *
 * `bothCount` must also clear `MIN_CONFOUNDER_CO_OCCURRENCES` on its own (#98): the rate check
 * above says nothing about sample size, so without this a single shared entry could pass at rate
 * 1.0 and come back `inseparable` — a tiny-sample flag of exactly the kind FR-008 exists to reject.
 * The production caller happens to pre-filter to `MIN_OCCURRENCE_THRESHOLD`, but this function is
 * exported and tested standalone and should not depend on a guarantee only its one caller keeps.
 */
export function confounderSplit(
  topicName: string,
  otherName: string,
  bothCount: number,
  onlyThisCount: number,
  onlyOtherCount: number,
  neitherCount: number,
): ConfounderSplit | null {
  if (bothCount < MIN_CONFOUNDER_CO_OCCURRENCES) return null;
  const thisTotal = bothCount + onlyThisCount;
  if (thisTotal === 0) return null;
  const coOccurrenceRate = bothCount / thisTotal;
  if (coOccurrenceRate < COLLINEARITY_THRESHOLD) return null;

  const inseparable = onlyThisCount === 0;
  const note = inseparable
    ? `${topicName} and ${otherName} appear together in all ${bothCount} of your ` +
      `${plural(bothCount, 'entry', 'entries')} mentioning ${topicName} — this diary cannot ` +
      `separate ${topicName} from ${otherName}.`
    : `${topicName} and ${otherName} appear together in ${bothCount} of ${thisTotal} ` +
      `${plural(thisTotal, 'entry', 'entries')} mentioning ${topicName} ` +
      `(${percent(coOccurrenceRate)}%) — the association with ${topicName} could really be ` +
      `about ${otherName}. Only ${onlyThisCount} ` +
      `${plural(onlyThisCount, 'entry separates', 'entries separate')} them.`;

  return {
    topic: otherName,
    coOccurrenceRate,
    bothCount,
    onlyThisCount,
    onlyOtherCount,
    neitherCount,
    inseparable,
    note,
  };
}

// ---------------------------------------------------------------------------------------------
// Valence averaging (I5)
// ---------------------------------------------------------------------------------------------

/**
 * Average valence over a bucket of entries.
 *
 * Each entry contributes the mean of its own feelings' scores, not one row per feeling: an entry
 * tagged with three negative words is one bad day, and letting it count three times would let a
 * verbose entry outvote a quiet week.
 */
export function averageValence(entries: Array<{ valences: string[] }>): number | null {
  const scored = entries
    .map((entry) => {
      const values = entry.valences
        .map((valence) => VALENCE_SCORE[valence])
        .filter((value): value is number => value !== undefined);
      return values.length === 0 ? null : values.reduce((a, b) => a + b, 0) / values.length;
    })
    .filter((value): value is number => value !== null);
  if (scored.length === 0) return null;
  return scored.reduce((a, b) => a + b, 0) / scored.length;
}

// ---------------------------------------------------------------------------------------------
// Trajectory signal (I6-05)
// ---------------------------------------------------------------------------------------------

/**
 * The single continuous number an entry contributes to a trajectory.
 *
 * User-set intensity when there is one, discrete valence when there is not — and never a blend of
 * the two in one number (I6-05). The scales measure different things: valence is direction on a
 * three-point axis, intensity is magnitude on a five-point one, and averaging a 4 with a −1 would
 * produce a figure that means nothing on either.
 *
 * The fallback maps valence onto the same −1…+1 range so a diary where the user rates some entries
 * and not others still yields one comparable series. An entry with no feeling at all contributes
 * nothing rather than zero, because "not recorded" is not "neutral".
 */
export function trajectorySignal(entry: {
  valence: string | null;
  intensity: number | null;
}): number | null {
  if (entry.valence === null) return null;
  const direction = VALENCE_SCORE[entry.valence];
  if (direction === undefined) return null;
  if (entry.intensity === null) return direction;
  // 1…5 becomes 0.2…1.0 of the valence's direction. A neutral feeling stays at zero however
  // strongly it was felt — intensity scales a direction, it does not invent one.
  return direction * (entry.intensity / MAX_INTENSITY);
}
