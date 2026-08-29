/**
 * TypeScript mirrors of the backend schemas (specs/003-web-client/contracts/api.md).
 *
 * These are shapes only. Constitution Principle VII keeps every rule — the feeling set, the
 * minimum-occurrence threshold, topic extraction, and all counts and averages — in the backend, so
 * nothing in this file computes anything or hardcodes a value the backend owns. `version` in
 * particular is opaque to the client: it is read, stored, and sent back untouched.
 */

export type Valence = 'positive' | 'neutral' | 'negative';

export interface Feeling {
  key: string;
  label: string;
  valence: Valence;
  /** Which group this feeling is picked inside. Decided by the backend, never by this client. */
  group_key: string;
}

/**
 * A group of related feelings — the first level of the picker.
 *
 * The vocabulary is too large to put on screen at once without slowing down the one flow that has
 * to stay fast (writing an entry), so a group is what the user chooses first and the feelings
 * inside it open on demand. Which group a feeling is in, and the group's valence, are the
 * backend's to decide (Principle VII); the accent colour each group is drawn in is this client's.
 */
export interface FeelingGroup {
  key: string;
  label: string;
  valence: Valence;
  feelings: Feeling[];
}

/** What `GET /feelings` returns: the same vocabulary nested and flat. */
export interface FeelingVocabulary {
  groups: FeelingGroup[];
  feelings: Feeling[];
}

export type EntryMode = 'guided' | 'freeform';

export type FeelingSource = 'unset' | 'suggested' | 'confirmed' | 'overridden';

export interface SuggestedFeeling {
  key: string;
  confidence: number;
}

export interface Entry {
  id: string;
  created_at: string;
  entry_date: string;
  mode: EntryMode;
  raw_text: string;
  /** The primary feeling — always `feeling_keys[0]`. Kept for the rail and the calendar dot. */
  feeling_key: string | null;
  /** Every feeling on the entry, in the order it was chosen. */
  feeling_keys: string[];
  feeling_source: FeelingSource;
  /**
   * How strongly the primary feeling was felt, 1–5, or null when the user never said (I6).
   *
   * Optional everywhere it appears. The scale's bounds are the backend's — this client sends what
   * the user picked and renders what comes back, and `constants.max_intensity` says how many stops
   * the dial has.
   */
  feeling_intensity: number | null;
  /**
   * How strongly each feeling on the entry was felt, keyed by feeling key (I6).
   *
   * Only feelings the user rated appear; an unrated feeling is absent rather than zero, because
   * "not asked" and "felt none of it" are different answers. `feeling_intensity` above is this map
   * read at `feeling_key`, kept for the calendar, which draws one dot and needs one number.
   */
  feeling_intensities: Record<string, number>;
  /**
   * The guiding questions this entry was written against, in the wording they were answered under.
   *
   * `null` means the endpoint did not load them; `[]` means the entry has none, which is every
   * freeform entry.
   */
  guided_answers: GuidedAnswer[] | null;
  suggested_feeling: SuggestedFeeling | null;
  suggested_feelings: SuggestedFeeling[];
  version: number;
}

/** One answered guiding question, as stored with the entry. */
export interface GuidedAnswer {
  question_key: string;
  /** How the question was worded when it was answered, not how it is worded now. */
  question_text: string;
  answer_text: string;
  order_index: number;
}

export interface GuidedAnswerInput {
  question_key: string;
  answer_text: string;
}

export interface EntryCreateInput {
  mode: EntryMode;
  raw_text: string;
  guided_answers?: GuidedAnswerInput[];
}

export interface EntryUpdateInput {
  raw_text?: string;
  feeling_keys?: string[];
  /** Legacy single-value form. Read by the backend as a rating of the primary feeling (I6-03). */
  feeling_intensity?: number | null;
  /**
   * One optional rating per feeling. Omit to leave the stored ratings alone; a map replaces them
   * outright, so an empty map is how every rating is cleared.
   */
  feeling_intensities?: Record<string, number>;
  version: number;
}

/**
 * Which part of the flow a guiding question belongs to.
 *
 * The three time slots joined the library with A6. They are optional prompts, and a client that
 * does not know a category simply shows the question without special placement — the API is
 * additive by design (A6-06).
 */
export type QuestionCategory =
  | 'general'
  | 'mind_body'
  | 'small_influences'
  | 'response_outcome'
  | 'morning'
  | 'afternoon'
  | 'evening';

export const TIME_SLOT_CATEGORIES: QuestionCategory[] = ['morning', 'afternoon', 'evening'];

export interface GuidingQuestion {
  key: string;
  category: QuestionCategory;
  prompt_text: string;
  trigger_keywords: string[];
  is_mandatory: boolean;
}

/**
 * The advice badge a pattern card carries (P0-2), derived once on the backend from the pattern's
 * `kind` and its feeling's valence — see `badgeDirectionFor` in
 * `backend/src/insights/patterns.service.ts`, the single function that decides it. `'none'` is a
 * neutral-valence feeling: no positive signal to reinforce and no negative one to discourage, so
 * there is nothing to advise, and this client renders no badge at all rather than defaulting to
 * one — see `PatternCard`.
 */
export type PatternDirection = 'keep' | 'change' | 'none';

/** Forward: the feeling went *with* the topic. Inverse: it went with the topic's absence (I1). */
export type PatternKind = 'forward' | 'inverse';

/** Active: enough evidence inside the recency window. Historical: the evidence is older (I3). */
export type PatternStatus = 'active' | 'historical';

/** One entry standing behind a pattern (A1). Rendered exactly as received — never re-filtered. */
export interface PatternEvidence {
  entry_id: string;
  entry_date: string;
  raw_text: string;
  feeling_keys: string[];
  feeling_source: FeelingSource;
}

/** Another topic this one keeps company with, and the split that shows it (I2). */
export interface Confounder {
  topic: string;
  co_occurrence_rate: number;
  both_count: number;
  only_this_count: number;
  only_other_count: number;
  neither_count: number;
  inseparable: boolean;
  note: string;
}

/**
 * R-1: a "Worth trying" card, attached to the pattern it was derived from — `null` for almost
 * every pattern, and present only for the top few (by lift) whose `direction` reads `'keep'`. See
 * `RecommendationOut` in `backend/src/insights/patterns.service.ts` for the full reasoning; `web`
 * has no UI for this yet (that is mobile's `features/insights/` work), so this type exists for wire
 * accuracy only.
 */
export interface PatternRecommendation {
  action_topic: string;
  headline: string;
  sentence: string;
  pattern_ref: string;
}

export interface Pattern {
  id: string;
  kind: PatternKind;
  topic: string;
  feeling: string;
  /** The windowed count — and, by construction, the length of `evidence` (A1-02). */
  occurrence_count: number;
  lifetime_count: number;
  status: PatternStatus;
  direction: PatternDirection;
  narrative_text: string;
  suggestion_text: string;
  present_count: number;
  present_total: number;
  absent_count: number;
  absent_total: number;
  present_rate: number | null;
  absent_rate: number | null;
  base_rate: number;
  /** How much likelier the feeling is with the topic than without it — or null, with a reason. */
  lift: number | null;
  comparison_reason: string | null;
  comparison_note: string | null;
  is_strong: boolean;
  last_occurrence_date: string | null;
  days_since_last_occurrence: number | null;
  historical_note: string | null;
  confounders: Confounder[];
  evidence: PatternEvidence[];
  last_updated_at: string;
  recommendation: PatternRecommendation | null;
}

/**
 * Why a pattern stopped qualifying. Decided by the backend from data, never by a model.
 *
 * `below_lift` and `below_threshold` are deliberately separate: one means the evidence thinned out,
 * the other means the evidence held and the *association* weakened. They call for different words,
 * and a client can only tell them apart if the code does.
 */
export type WithdrawalReason =
  'below_threshold' | 'below_lift' | 'no_longer_confirmed' | 'topic_merged';

/** A pattern that stopped qualifying, and the numbers that say why (A2). */
export interface Withdrawal {
  id: string;
  topic: string;
  feeling: string;
  kind: PatternKind;
  previous_count: number;
  new_count: number;
  reason: WithdrawalReason;
  detail_text: string;
  withdrawn_at: string;
  is_new: boolean;
}

/**
 * Every threshold the engine applied, served with the answer.
 *
 * Read, never assumed. Constitution Principle VII puts these in the backend, so the client saying
 * "in the last 30 days" reads the 30 from here rather than from a constant of its own — otherwise
 * a change to the window would silently make this client's wording false.
 */
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

export interface Insights {
  patterns: Pattern[];
  withdrawals: Withdrawal[];
  new_withdrawal_count: number;
  insufficient_data: boolean;
  constants: EngineConstants;
}

/** One weekday or time-of-day bucket in the "when" view (I5). */
export interface WhenBucket {
  key: string;
  label: string;
  entry_count: number;
  /** Mean valence on the −1 … +1 scale, or null when the bucket is too thin to average. */
  average_valence: number | null;
  negative_rate: number | null;
  sufficient: boolean;
}

export interface WhenInsights {
  window_days: number;
  min_bucket_entries: number;
  total_entries: number;
  weekdays: WhenBucket[];
  times_of_day: WhenBucket[];
  best_weekday: string | null;
  worst_weekday: string | null;
  best_time_of_day: string | null;
  worst_time_of_day: string | null;
}

/** What the diary already says about the topics in an entry just saved (I4). */
export interface PatternEcho {
  pattern_id: string;
  topic: string;
  feeling: string;
  kind: PatternKind;
  status: PatternStatus;
  occurrence_count: number;
  present_count: number;
  present_total: number;
  lift: number | null;
  narrative_text: string;
}

/** A topic and the spellings the user has taught the app to fold into it (A4-04). */
export interface TopicDetail {
  id: string;
  name: string;
  aliases: string[];
  entry_count: number;
}

export interface MonthlyDay {
  date: string;
  feelings: string[];
  /** The strongest intensity recorded that day, or null when nothing was rated (I6-04). */
  intensity: number | null;
  /**
   * The number of entries logged that day (#72). Not the same number as `feelings.length` — an
   * entry can share a feeling with others that day, or carry none at all, so this counts entries
   * directly rather than deriving from the feeling set.
   */
  entry_count: number;
}

export interface MonthlySummary {
  month: string;
  days: MonthlyDay[];
  totals_by_feeling: Record<string, number>;
  average_entries_per_day: number;
}
