import type { NaiveDateTime, PlainDate } from '../db/codecs';

export type EntryMode = 'guided' | 'freeform';
export type FeelingSource = 'unset' | 'suggested' | 'confirmed' | 'overridden';
/**
 * Where an entry came from (L-1b, #35): `'app'` for the normal compose flow, `'daylio_import'` for
 * a row the Daylio CSV importer wrote. Distinct from `FeelingSource` — that describes how the
 * *feeling* was decided; this describes where the *entry* itself originated, and is what makes
 * imported history visibly, permanently distinguishable from what the user typed here.
 */
export type EntryOrigin = 'app' | 'daylio_import';
export type Valence = 'positive' | 'neutral' | 'negative';

/**
 * The advice badge a pattern card carries (P0-2), derived once from the pattern's `kind` and its
 * feeling's `valence` — see `insights/patterns.service.ts#badgeDirectionFor`, the single function
 * that owns the mapping. `'none'` is a neutral-valence feeling: no positive signal to reinforce
 * and no negative one to discourage, so there is nothing to advise, and both clients render it as
 * no badge rather than inventing one.
 *
 * Distinct from the two-valued direction persisted on the `patterns` row (`'keep' | 'change'`,
 * still `directionFor` in the same file): that field predates this badge, feeds
 * `inference/worker.ts`'s suggestion-phrasing prompt and is checked by `db/compatibility.ts` on
 * every startup, and neither has a "no opinion" state to spend, so a neutral pattern still
 * collapses to `'change'` there, unchanged.
 */
export type PatternDirection = 'keep' | 'change' | 'none';

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
  /** Where this entry came from (L-1b, #35) — `'app'` for every entry written before this ticket. */
  origin: EntryOrigin;
}

export interface SuggestedFeeling {
  key: string;
  confidence: number;
}

/**
 * How a topic↔feeling pairing came to be stored — the same three-state provenance
 * `FeelingSource` carries, minus `'unset'`: a pairing nobody proposed or chose simply has no row
 * (E-1a), the same way a topic no entry mentions has no `entry_topics` row.
 */
export type PairingSource = 'suggested' | 'confirmed' | 'overridden';

/**
 * One topic↔feeling link on an entry (E-1a) — the sub-entry attribution that keeps a mixed-valence
 * entry ("missed my workout, disappointing — but a lovely call with my family") from feeding false
 * pairs into the pattern engine (workout×grateful, family×disappointed). `topic` is carried
 * alongside `topicId` so a pairing is self-describing without a client cross-referencing the
 * entry's separate `topics` list (#81, `TopicsService.topicsForEntry()`) — and unlike that list,
 * a topic the engine could not pair with any feeling simply has no row here at all.
 */
export interface TopicFeelingPairing {
  topicId: string;
  topic: string;
  feelingKey: string;
  source: PairingSource;
}
