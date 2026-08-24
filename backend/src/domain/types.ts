import type { NaiveDateTime, PlainDate } from '../db/codecs';

export type EntryMode = 'guided' | 'freeform';
export type FeelingSource = 'unset' | 'suggested' | 'confirmed' | 'overridden';
export type Valence = 'positive' | 'neutral' | 'negative';
export type PatternDirection = 'keep' | 'change';

export interface Feeling {
  key: string;
  label: string;
  valence: Valence;
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
  feelingKey: string | null;
  feelingSource: FeelingSource;
  version: number;
}

export interface SuggestedFeeling {
  key: string;
  confidence: number;
}
