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
  feeling_key: string | null;
  feeling_source: FeelingSource;
  suggested_feeling: SuggestedFeeling | null;
  version: number;
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
  feeling_key?: string;
  version: number;
}

export type QuestionCategory = 'general' | 'mind_body' | 'small_influences' | 'response_outcome';

export interface GuidingQuestion {
  key: string;
  category: QuestionCategory;
  prompt_text: string;
  trigger_keywords: string[];
  is_mandatory: boolean;
}

export type PatternDirection = 'keep' | 'change';

export interface Pattern {
  id: string;
  topic: string;
  feeling: string;
  occurrence_count: number;
  direction: PatternDirection;
  narrative_text: string;
  suggestion_text: string;
  last_updated_at: string;
}

export interface Insights {
  patterns: Pattern[];
  insufficient_data: boolean;
}

export interface MonthlyDay {
  date: string;
  feelings: string[];
}

export interface MonthlySummary {
  month: string;
  days: MonthlyDay[];
  totals_by_feeling: Record<string, number>;
  average_entries_per_day: number;
}
