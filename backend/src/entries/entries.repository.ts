import { Inject, Injectable } from '@nestjs/common';
import { decodeBool, decodeDate, decodeDateTime, decodeJson, encodeDate } from '../db/codecs';
import { DIARY_DB } from '../db/database.provider';
import type { DiaryDatabase } from '../db/database';
import type {
  DiaryEntry,
  EntryMode,
  Feeling,
  FeelingSource,
  GuidedAnswer,
  GuidingQuestion,
  Valence,
} from '../domain/types';
import type { PlainDate } from '../db/codecs';
import { GUIDED_DRAFT_SENTINEL } from './guided-draft';

interface EntryRow {
  id: string;
  created_at: string;
  updated_at: string;
  entry_date: string;
  mode: string;
  raw_text: string;
  feeling_key: string | null;
  feeling_source: string;
  version: number;
}

function toEntry(row: EntryRow): DiaryEntry {
  return {
    id: row.id,
    createdAt: decodeDateTime(row.created_at),
    updatedAt: decodeDateTime(row.updated_at),
    entryDate: decodeDate(row.entry_date),
    mode: row.mode as EntryMode,
    rawText: row.raw_text,
    feelingKey: row.feeling_key,
    feelingSource: row.feeling_source as FeelingSource,
    version: Number(row.version),
  };
}

@Injectable()
export class EntriesRepository {
  constructor(@Inject(DIARY_DB) private readonly db: DiaryDatabase) {}

  findByDate(date: PlainDate): DiaryEntry[] {
    // Ordered by created_at — User Story 1's acceptance criteria.
    const rows = this.db
      .prepare<EntryRow>(
        'SELECT * FROM diary_entries WHERE entry_date = ? AND raw_text <> ? ORDER BY created_at',
      )
      .all(encodeDate(date), GUIDED_DRAFT_SENTINEL) as EntryRow[];
    return rows.map(toEntry);
  }

  findById(id: string): DiaryEntry | null {
    const row = this.db
      .prepare<EntryRow>('SELECT * FROM diary_entries WHERE id = ? AND raw_text <> ?')
      .get(id, GUIDED_DRAFT_SENTINEL) as EntryRow | undefined;
    return row ? toEntry(row) : null;
  }

  findAll(): DiaryEntry[] {
    const rows = this.db
      .prepare<EntryRow>('SELECT * FROM diary_entries WHERE raw_text <> ? ORDER BY created_at')
      .all(GUIDED_DRAFT_SENTINEL) as EntryRow[];
    return rows.map(toEntry);
  }

  findInDateRange(start: PlainDate, end: PlainDate): DiaryEntry[] {
    const rows = this.db
      .prepare<EntryRow>(
        `SELECT * FROM diary_entries WHERE entry_date >= ? AND entry_date <= ? AND raw_text <> ?
         ORDER BY created_at`,
      )
      .all(encodeDate(start), encodeDate(end), GUIDED_DRAFT_SENTINEL) as EntryRow[];
    return rows.map(toEntry);
  }

  findGuidedAnswers(entryId: string): GuidedAnswer[] {
    const rows = this.db
      .prepare('SELECT * FROM guiding_question_answers WHERE entry_id = ? ORDER BY order_index')
      .all(entryId) as Array<{
      id: string;
      entry_id: string;
      question_key: string;
      question_text_snapshot: string;
      answer_text: string;
      order_index: number;
    }>;
    return rows.map((r) => ({
      id: r.id,
      entryId: r.entry_id,
      questionKey: r.question_key,
      questionTextSnapshot: r.question_text_snapshot,
      answerText: r.answer_text,
      orderIndex: Number(r.order_index),
    }));
  }
}

@Injectable()
export class FeelingsRepository {
  constructor(@Inject(DIARY_DB) private readonly db: DiaryDatabase) {}

  findAll(): Feeling[] {
    // No ORDER BY: SQLite returns rows in insertion order, which is the seed order the clients
    // expect. Both render what they are given.
    const rows = this.db.prepare('SELECT "key", label, valence FROM feelings').all() as Array<{
      key: string;
      label: string;
      valence: string;
    }>;
    return rows.map((r) => ({ key: r.key, label: r.label, valence: r.valence as Valence }));
  }
}

@Injectable()
export class GuidingQuestionsRepository {
  constructor(@Inject(DIARY_DB) private readonly db: DiaryDatabase) {}

  findAll(): GuidingQuestion[] {
    const rows = this.db
      .prepare(
        'SELECT "key", category, prompt_text, trigger_keywords, is_mandatory FROM guiding_questions',
      )
      .all() as Array<{
      key: string;
      category: string;
      prompt_text: string;
      trigger_keywords: string;
      is_mandatory: number;
    }>;
    return rows.map((r) => ({
      key: r.key,
      category: r.category,
      promptText: r.prompt_text,
      triggerKeywords: decodeJson<string[]>(r.trigger_keywords),
      isMandatory: decodeBool(r.is_mandatory),
    }));
  }
}
