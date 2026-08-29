/**
 * Every threshold, window and scale the insight engine applies.
 *
 * They live in one file, apart from the services that use them, for the reason the constitution
 * gives in Principle VII: a number a client hardcodes is a number the two clients can disagree
 * about. `GET /insights` serves this whole block back as `constants`, so web and Android render
 * "the last 30 days" and "at least 3 times" from the same source that decided them.
 *
 * Nothing here is a preference. Each value changes which patterns a user is shown, so changing one
 * is changing the product's claim about their diary — hence the reasoning beside each.
 */

/** FR-008: fewer than three co-occurrences is a coincidence, not a pattern. */
export const MIN_OCCURRENCE_THRESHOLD = 3;

/**
 * How far back "recent" reaches (I3-01).
 *
 * The engine counted lifetime occurrences while the narrative said "recent", which made the
 * sentence false for any diary older than a month. The window is now the count's actual meaning,
 * and the narrative is generated from the same number.
 */
export const RECENCY_WINDOW_DAYS = 30;

/**
 * How much more likely the feeling must be with the topic than without it (A3-04).
 *
 * 1.5x is the floor at which the association is worth a card. Below it the pair is arithmetic
 * noise: three "tired" entries mentioning work prove nothing about work if the user is tired most
 * days, and the ≥3 rule alone cannot tell those two situations apart.
 */
export const MIN_LIFT = 1.5;

/** A pattern strong enough to mark visually (A3-07) — both conditions must hold. */
export const STRONG_LIFT = 3.0;
export const STRONG_MIN_OCCURRENCES = 5;

/**
 * The smallest usable comparison group (A3-05 / I1-08).
 *
 * With fewer entries on the other side, the "without" rate is one or two entries wide and a single
 * entry swings it from 0% to 50%. The pattern is still shown — withholding it would contradict the
 * app's own explainability principle — but it is shown with the note instead of a lift number.
 */
export const MIN_COMPARISON_ENTRIES = 3;

/** Two topics this entangled cannot be told apart in this diary (I2-02). */
export const COLLINEARITY_THRESHOLD = 0.8;

/**
 * #98: the floor on `bothCount` a confounder split needs before it can be reported at all,
 * independent of the rate `COLLINEARITY_THRESHOLD` checks.
 *
 * `confounderSplit`'s only production caller (`PatternsService.confoundersFor`) already restricts
 * candidates to `MIN_OCCURRENCE_THRESHOLD` (3) co-occurrences before the rate check ever runs, so a
 * rate ≥ 0.8 already implies `bothCount ≥ 3` there — but that is a property of the caller, not
 * something the function itself guarantees. `confounderSplit` is exported and unit-tested as a
 * standalone pure function; without an explicit floor here, `confounderSplit('work', 'coffee', 1,
 * 0, 0, 5)` returns a confident "cannot separate" verdict off a single entry, which is exactly the
 * tiny-sample flag the rest of this file refuses to make (see the module doc comment). Set equal to
 * `MIN_OCCURRENCE_THRESHOLD` rather than inlining a second literal, since both express the same
 * "three occurrences is the smallest count worth calling a pattern" rule from FR-008 — a future
 * change to one is a reason to look at the other, not a coincidence to hide.
 *
 * Not part of `EngineConstants` / the `GET /insights` `constants` block below: that block exists so
 * a client never has to hardcode a threshold it needs to interpret or reproduce a number it is
 * shown. No client reads `bothCount` independently of the `ConfounderSplit` the server already
 * decided on — the guard is enforced before a split is ever returned, so there is no client-side
 * decision this number would inform. Add it there if a client ever needs to explain *why* a
 * candidate produced no confounder note.
 */
export const MIN_CONFOUNDER_CO_OCCURRENCES = 3;

/** A2-06: withdrawal history is a notice board, not an archive. */
export const MAX_WITHDRAWAL_RECORDS = 50;

/** I1-06: inverse patterns rank by lift and are capped so they never flood the forward list. */
export const MAX_INVERSE_PATTERNS = 5;

/**
 * R-1: how many patterns can carry a "Worth trying" recommendation at once, ranked by lift the same
 * way `MAX_INVERSE_PATTERNS`/`MAX_CONTEXT_PATTERNS` cap their own lists. Not part of
 * `EngineConstants` below, for the same reason those two aren't: it is a server-side flooding guard
 * on how many cards get promoted, not a threshold a client evaluates a number against.
 */
export const MAX_RECOMMENDATIONS = 3;

/** I5-02: a weekday or time bucket below this is reported as insufficient, never as an average. */
export const MIN_BUCKET_ENTRIES = 3;

/**
 * The valence scale used for every average the "when" view — and every chart — shows (I5-03).
 *
 * Deliberately three points and not five: the diary stores a feeling word, not a rating, and
 * inventing intermediate values would give the average a precision the data does not have.
 * Intensity (I6) is a separate, user-set scale and is never mixed into this one.
 */
export const VALENCE_SCORE: Record<string, number> = {
  positive: 1,
  neutral: 0,
  negative: -1,
};

/**
 * The day score (CH-0): the number every chart — the mood line, Year in Pixels, the topic
 * sparkline — is built from, defined once so the two clients never invent their own.
 *
 * A day's score is the **mean `VALENCE_SCORE` of its CONFIRMED feelings** (`CONFIRMED_FEELING_SOURCES`
 * below — a suggestion nobody acted on is not evidence here either, same as everywhere else in this
 * engine), flattened across every feeling on every confirmed entry that day rather than averaged
 * per entry first. A day with entries but zero confirmed feelings scores `null`, not `0` — "nothing
 * confirmed" and "confirmed neutral" are different facts, and the entry count travels alongside so a
 * client can still draw the day faintly instead of pretending it never happened. A day with no
 * entries at all does not appear in the series — a gap is a gap, not a `null`.
 *
 * `feeling_intensity` (I6) is deliberately never folded in: intensity is optional, most days will
 * not have it, and mixing an optional 1–5 rating into a −1…+1 mean would make the line dishonest
 * about days that were never rated. An intensity-weighted line, if one ships, is a separate opt-in
 * series that only draws over rated days — never a silent adjustment to this one.
 *
 * Week and month points aggregate by the **mean of day scores**, not by pooling every feeling in the
 * period — a single heavy day (many entries, many feelings) would otherwise outvote a quiet week
 * instead of counting once, the same reasoning `averageValence` in `analysis.ts` applies per entry.
 *
 * See `src/insights/series.service.ts` for the implementation this describes.
 */

/** CH-0: the largest `from`…`to` span `GET /insights/series` accepts at `granularity=day`. */
export const MAX_SERIES_RANGE_DAYS = 400;

/** I6: the optional dial on the primary feeling. Not a 1–100 scale (I6-08). */
export const MIN_INTENSITY = 1;
export const MAX_INTENSITY = 5;

/** I5-01: the three buckets `created_at` is sorted into, and the hours each covers. */
export const TIME_OF_DAY_BUCKETS = [
  { key: 'morning', label: 'Morning', startHour: 5, endHour: 12 },
  { key: 'afternoon', label: 'Afternoon', startHour: 12, endHour: 18 },
  { key: 'evening', label: 'Evening', startHour: 18, endHour: 5 },
] as const;

export type TimeOfDayKey = (typeof TIME_OF_DAY_BUCKETS)[number]['key'];

/**
 * CH-5: the twelve 2-hour blocks the "when" heat strip renders `created_at` into.
 *
 * Finer than `TIME_OF_DAY_BUCKETS` above — which is unchanged, and still what the weekday/
 * time-of-day rows use — but coarser than by-the-hour, which would fragment diary-sized data past
 * `MIN_BUCKET_ENTRIES` in most cells (a full 24 is overkill at diary volumes). Fixed 2-hour-aligned
 * blocks starting at midnight, not the three named periods' skewed widths, so every cell in the
 * strip represents the same span of clock time and the twelve cells tile the day exactly once.
 *
 * `key` is the block's zero-padded start hour ("00", "02", … "22") rather than a name — the heat
 * strip has no room for a label per cell, so both clients read the start hour directly off the key
 * instead of parsing one out of `label`.
 */
export const HOUR_BLOCKS = Array.from({ length: 12 }, (_unused, index) => {
  const startHour = index * 2;
  const pad = (hour: number) => String(hour % 24).padStart(2, '0');
  return {
    key: pad(startHour),
    label: `${pad(startHour)}:00–${pad(startHour + 2)}:00`,
    startHour,
  };
});

export type HourBlockKey = (typeof HOUR_BLOCKS)[number]['key'];

export const WEEKDAYS = [
  { key: 'monday', label: 'Monday' },
  { key: 'tuesday', label: 'Tuesday' },
  { key: 'wednesday', label: 'Wednesday' },
  { key: 'thursday', label: 'Thursday' },
  { key: 'friday', label: 'Friday' },
  { key: 'saturday', label: 'Saturday' },
  { key: 'sunday', label: 'Sunday' },
] as const;

/** #21: `weekdayIndex` ≥ this is Saturday or Sunday — the only two days `dayTypeFor` calls a weekend. */
export const WEEKEND_START_INDEX = 5;

export const DAY_TYPES = [
  { key: 'weekday', label: 'Weekday' },
  { key: 'weekend', label: 'Weekend' },
] as const;
export type DayTypeKey = (typeof DAY_TYPES)[number]['key'];

/**
 * #21: which months fall in which meteorological season, northern-hemisphere convention — the same
 * one implied everywhere else a season word already appears in the product's copy. Astronomical
 * boundaries (equinox/solstice dates) were rejected: they move by a day or two each year, which
 * would make the same calendar date file under a different season depending on when the diary is
 * read, and this engine's whole premise is that a number is reproducible from the diary alone.
 */
export const SEASONS = [
  { key: 'winter', label: 'Winter', months: [12, 1, 2] },
  { key: 'spring', label: 'Spring', months: [3, 4, 5] },
  { key: 'summer', label: 'Summer', months: [6, 7, 8] },
  { key: 'autumn', label: 'Autumn', months: [9, 10, 11] },
] as const;
export type SeasonKey = (typeof SEASONS)[number]['key'];

/**
 * #21: the passive context factors an entry carries, purely from `entry_date` and `created_at` — no
 * schema change, no stored rows (see `analysis.ts#contextFactorsForEntry`, the only place these keys
 * are derived). `phrase` is the fragment `analysis.ts#contextNarrative` drops into "You felt X in N
 * of M entries {phrase} …", so every context pattern's wording comes from this one table rather than
 * a switch statement client code and server code could each write differently.
 */
export const CONTEXT_FACTORS: ReadonlyArray<{
  key: string;
  category: 'weekday' | 'daytype' | 'timeofday' | 'season';
  label: string;
  phrase: string;
}> = [
  ...WEEKDAYS.map((day) => ({
    key: `weekday:${day.key}`,
    category: 'weekday' as const,
    label: day.label,
    phrase: `on ${day.label}s`,
  })),
  ...DAY_TYPES.map((dayType) => ({
    key: `daytype:${dayType.key}`,
    category: 'daytype' as const,
    label: dayType.label,
    phrase: `on ${dayType.label.toLowerCase()}s`,
  })),
  ...TIME_OF_DAY_BUCKETS.map((bucket) => ({
    key: `timeofday:${bucket.key}`,
    category: 'timeofday' as const,
    label: bucket.label,
    phrase: `in the ${bucket.label.toLowerCase()}`,
  })),
  ...SEASONS.map((season) => ({
    key: `season:${season.key}`,
    category: 'season' as const,
    label: season.label,
    phrase: `in ${season.label.toLowerCase()}`,
  })),
];

/**
 * I1-06's counterpart for context patterns (#21 task 4): with 16 candidate factors × every
 * confirmed feeling, an unranked list could show more "time of day" cards than topic ones. Ranked
 * by lift, same as `MAX_INVERSE_PATTERNS`, and for the same reason.
 */
export const MAX_CONTEXT_PATTERNS = 8;

/** Only a feeling the user acted on is evidence — a mere suggestion is not a fact (FR-012, C-04). */
export const CONFIRMED_FEELING_SOURCES = ['confirmed', 'overridden'];

/**
 * #37 (L-2): once a diary has this many surfaced topic×feeling patterns, the insight progress
 * surface's job — filling the cold-start gap before the first pattern exists — is done, and the
 * pattern echo owns the "Entry saved" screen from here (`ProgressService#forEntry`).
 *
 * Coincidentally equal to `MIN_OCCURRENCE_THRESHOLD` in today's product, but a different fact about
 * a different unit — that one counts occurrences of a single pair, this one counts how many pairs
 * have themselves already become patterns — so it is kept as its own named constant rather than a
 * second use of that one. Each is free to change without silently moving the other. Not part of
 * `EngineConstants`/`engineConstants()` below: it never travels over `GET /insights`, only over the
 * progress payload it gates (`ProgressOut.surfaced_pattern_gate`) — the same "a client never
 * hardcodes a number it has to compare against" rule this file's module doc comment states, applied
 * to the one screen that actually needs this particular number.
 */
export const SURFACED_PATTERN_GATE = 3;

/**
 * #88: pacing for the background narration worker (`src/inference/worker.ts`).
 *
 * Not part of `EngineConstants` below — these govern the worker's own request cadence, never a
 * client-visible claim about the diary, so they have no reason to travel over `GET /insights`.
 * They live here anyway, alongside every other tunable the engine applies, rather than as literals
 * buried in the worker loop.
 *
 * The root defect (#88) was a rejected narration attempt reporting itself as "work done", which let
 * the loop retry the same pattern immediately, forever, with no delay between calls to the model.
 * These three numbers are what replace that: a cap so one unnarratable pattern cannot hold the
 * model hostage, backoff so a retry is not immediate, and a floor on how often the worker is
 * willing to call the model at all, regardless of which pattern it is trying.
 */

/** A pattern whose advice keeps getting rejected stops being retried after this many attempts. */
export const MAX_NARRATION_ATTEMPTS = 5;

/** The first backoff after a rejected attempt — doubled on every attempt after that. */
export const NARRATION_BACKOFF_BASE_MS = 60_000;

/** However many attempts a pattern has racked up, its backoff never exceeds this. */
export const NARRATION_BACKOFF_MAX_MS = 30 * 60_000;

/**
 * The token bucket: the worker will not start a narration model call more often than this,
 * regardless of outcome — a written suggestion is exactly as throttled as a rejected one. Actual
 * user-facing work (`entry_analysis`) is never subject to this: `claimNext` is re-checked at the
 * top of every loop iteration, so a queued job always preempts narration on the very next tick.
 */
export const NARRATION_MIN_INTERVAL_MS = 5_000;

/** Everything above, in the shape `GET /insights` serves to clients (C-01). */
export interface EngineConstants {
  min_occurrence_threshold: number;
  recency_window_days: number;
  min_lift: number;
  strong_lift: number;
  strong_min_occurrences: number;
  min_comparison_entries: number;
  collinearity_threshold: number;
  min_bucket_entries: number;
  min_intensity: number;
  max_intensity: number;
}

export function engineConstants(): EngineConstants {
  return {
    min_occurrence_threshold: MIN_OCCURRENCE_THRESHOLD,
    recency_window_days: RECENCY_WINDOW_DAYS,
    min_lift: MIN_LIFT,
    strong_lift: STRONG_LIFT,
    strong_min_occurrences: STRONG_MIN_OCCURRENCES,
    min_comparison_entries: MIN_COMPARISON_ENTRIES,
    collinearity_threshold: COLLINEARITY_THRESHOLD,
    min_bucket_entries: MIN_BUCKET_ENTRIES,
    min_intensity: MIN_INTENSITY,
    max_intensity: MAX_INTENSITY,
  };
}
