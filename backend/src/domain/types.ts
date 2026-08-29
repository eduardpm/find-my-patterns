import type { NaiveDateTime, PlainDate } from '../db/codecs';

export type EntryMode = 'guided' | 'freeform';
export type FeelingSource = 'unset' | 'suggested' | 'confirmed' | 'overridden';
export type Valence = 'positive' | 'neutral' | 'negative';
export type PatternDirection = 'keep' | 'change';

export interface Feeling {
  key: string;
  label: string;
  valence: Valence;
  /** The group this feeling is picked inside — see `db/feeling-vocabulary.ts`. */
  groupKey: string;
}

/**
 * One of the handful of buckets the vocabulary is organised into. Both clients show these first
 * and open the group's own feelings on demand, which is the only reason a 30-word vocabulary fits
 * in the entry flow without slowing it down (Principle VI).
 *
 * A group's valence always matches every feeling inside it, so a client may tint a whole group
 * with one accent without inventing a rule of its own.
 */
export interface FeelingGroup {
  key: string;
  label: string;
  valence: Valence;
  feelings: Feeling[];
}

export interface GuidingQuestion {
  key: string;
  category: string;
  promptText: string;
  triggerKeywords: string[];
  isMandatory: boolean;
}

export interface GuidedAnswer {
  id: string;
  entryId: string;
  questionKey: string;
  questionTextSnapshot: string;
  answerText: string;
  orderIndex: number;
}

export interface DiaryEntry {
  id: string;
  createdAt: NaiveDateTime;
  updatedAt: NaiveDateTime;
  entryDate: PlainDate;
  mode: EntryMode;
  rawText: string;
  /**
   * The entry's primary feeling — always `feelingKeys[0]`, or null when nothing is chosen.
   *
   * It is a denormalisation of `entry_feelings`, kept because it is what the calendar dot, the
   * entry card's rail and pattern rows are keyed on, and because every existing diary already
   * stores it. It is only ever written together with the set; nothing may set it independently,
   * or the two would start telling different stories about the same entry.
   */
  feelingKey: string | null;
  /** Every feeling on the entry, in the order the user (or the analyser) put them in. */
  feelingKeys: string[];
  feelingSource: FeelingSource;
  version: number;
  /**
   * How strongly the primary feeling was felt, 1–5, or null (I6).
   *
   * Optional by requirement, and set by the user only. The analyser's confidence is a different
   * quantity measured on a different thing — how sure the model is, not how much the user felt —
   * and is never stored or shown here (I6-02).
   */
  feelingIntensity: number | null;
  /**
   * How strongly each feeling on the entry was felt, keyed by feeling key (I6 revisited).
   *
   * Only feelings the user actually rated appear; an unrated feeling is absent rather than zero,
   * because "not asked" and "felt none of it" are different answers. [feelingIntensity] is this
   * map read at [feelingKey] — the two can never disagree, because both are written together.
   */
  feelingIntensities: Record<string, number>;
}

export interface SuggestedFeeling {
  key: string;
  confidence: number;
}
