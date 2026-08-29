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

/** A2-06: withdrawal history is a notice board, not an archive. */
export const MAX_WITHDRAWAL_RECORDS = 50;

/** I1-06: inverse patterns rank by lift and are capped so they never flood the forward list. */
export const MAX_INVERSE_PATTERNS = 5;

/** I5-02: a weekday or time bucket below this is reported as insufficient, never as an average. */
export const MIN_BUCKET_ENTRIES = 3;

/**
 * The valence scale used for every average the "when" view shows (I5-03).
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

export const WEEKDAYS = [
  { key: 'monday', label: 'Monday' },
  { key: 'tuesday', label: 'Tuesday' },
  { key: 'wednesday', label: 'Wednesday' },
  { key: 'thursday', label: 'Thursday' },
  { key: 'friday', label: 'Friday' },
  { key: 'saturday', label: 'Saturday' },
  { key: 'sunday', label: 'Sunday' },
] as const;

/** Only a feeling the user acted on is evidence — a mere suggestion is not a fact (FR-012, C-04). */
export const CONFIRMED_FEELING_SOURCES = ['confirmed', 'overridden'];

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
