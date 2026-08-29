import { Inject, Injectable } from '@nestjs/common';
import { decodeBool, decodeDate, decodeDateTime, decodeJson, encodeDate } from '../db/codecs';
import { DIARY_DB } from '../db/database.provider';
import type { DiaryDatabase } from '../db/database';
import type {
  DiaryEntry,
  EntryMode,
  Feeling,
  FeelingGroup,
  FeelingSource,
  GuidedAnswer,
  GuidingQuestion,
  Valence,
} from '../domain/types';
import type { PlainDate } from '../db/codecs';
import { GUIDED_DRAFT_SENTINEL } from './guided-draft';

/** One entry's feelings as stored: the ordered keys, plus whichever of them carry a rating. */
interface FeelingSet {
  keys: string[];
  intensities: Record<string, number>;
}

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
  feeling_intensity: number | null;
}

function toEntry(
  row: EntryRow,
  feelingKeys: string[],
  feelingIntensities: Record<string, number>,
): DiaryEntry {
  return {
    id: row.id,
    createdAt: decodeDateTime(row.created_at),
    updatedAt: decodeDateTime(row.updated_at),
    entryDate: decodeDate(row.entry_date),
    mode: row.mode as EntryMode,
    rawText: row.raw_text,
    feelingKey: row.feeling_key,
    feelingKeys,
    feelingSource: row.feeling_source as FeelingSource,
    version: Number(row.version),
    feelingIntensity:
      row.feeling_intensity === null || row.feeling_intensity === undefined
        ? null
        : Number(row.feeling_intensity),
    feelingIntensities,
  };
}

@Injectable()
export class EntriesRepository {
  constructor(@Inject(DIARY_DB) private readonly db: DiaryDatabase) {}

  /**
   * The feeling sets for a batch of entries, in one query.
   *
   * Per-entry lookups would be simpler to write and are the reason list endpoints quietly become
   * N+1 queries; a day or a month of entries is read in one go everywhere else in this class, and
   * their feelings are read the same way.
   */
  private feelingKeysFor(entryIds: string[]): Map<string, FeelingSet> {
    const byEntry = new Map<string, FeelingSet>();
    if (entryIds.length === 0) return byEntry;
    const rows = this.db
      .prepare(
        `SELECT entry_id, feeling_key, intensity FROM entry_feelings
         WHERE entry_id IN (${entryIds.map(() => '?').join(', ')})
         ORDER BY entry_id, position, feeling_key`,
      )
      .all(...entryIds) as Array<{
      entry_id: string;
      feeling_key: string;
      intensity: number | null;
    }>;
    for (const row of rows) {
      let set = byEntry.get(row.entry_id);
      if (!set) {
        set = { keys: [], intensities: {} };
        byEntry.set(row.entry_id, set);
      }
      set.keys.push(row.feeling_key);
      // Absent rather than null: an unrated feeling has no entry in the map at all, so a client
      // reading it cannot mistake "never rated" for a stored zero.
      if (row.intensity !== null && row.intensity !== undefined) {
        set.intensities[row.feeling_key] = Number(row.intensity);
      }
    }
    return byEntry;
  }

  private hydrate(rows: EntryRow[]): DiaryEntry[] {
    const feelings = this.feelingKeysFor(rows.map((row) => row.id));
    return rows.map((row) => {
      const set = feelings.get(row.id);
      return toEntry(row, set?.keys ?? [], set?.intensities ?? {});
    });
  }

  findByDate(date: PlainDate): DiaryEntry[] {
    // Ordered by created_at — User Story 1's acceptance criteria.
    const rows = this.db
      .prepare<EntryRow>(
        'SELECT * FROM diary_entries WHERE entry_date = ? AND raw_text <> ? ORDER BY created_at',
      )
      .all(encodeDate(date), GUIDED_DRAFT_SENTINEL) as EntryRow[];
    return this.hydrate(rows);
  }

  findById(id: string): DiaryEntry | null {
    const row = this.db
      .prepare<EntryRow>('SELECT * FROM diary_entries WHERE id = ? AND raw_text <> ?')
      .get(id, GUIDED_DRAFT_SENTINEL) as EntryRow | undefined;
    return row ? this.hydrate([row])[0] : null;
  }

  findAll(): DiaryEntry[] {
    const rows = this.db
      .prepare<EntryRow>('SELECT * FROM diary_entries WHERE raw_text <> ? ORDER BY created_at')
      .all(GUIDED_DRAFT_SENTINEL) as EntryRow[];
    return this.hydrate(rows);
  }

  findInDateRange(start: PlainDate, end: PlainDate): DiaryEntry[] {
    const rows = this.db
      .prepare<EntryRow>(
        `SELECT * FROM diary_entries WHERE entry_date >= ? AND entry_date <= ? AND raw_text <> ?
         ORDER BY created_at`,
      )
      .all(encodeDate(start), encodeDate(end), GUIDED_DRAFT_SENTINEL) as EntryRow[];
    return this.hydrate(rows);
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

  /**
   * The whole vocabulary, flat, in vocabulary order.
   *
   * Ordered explicitly by `sort_order` rather than relying on SQLite's insertion order, which is
   * what this used to do. Insertion order stopped being the right answer the moment a diary could
   * gain feelings through `migrate-db`: a feeling added to the middle of a group would otherwise
   * be appended to the end of the list on a migrated diary and sit in its group on a fresh one,
   * and the two clients would disagree about the order of the same vocabulary.
   */
  findAll(): Feeling[] {
    const rows = this.db
      .prepare('SELECT "key", label, valence, group_key FROM feelings ORDER BY sort_order, "key"')
      .all() as Array<{
      key: string;
      label: string;
      valence: string;
      group_key: string;
    }>;
    return rows.map((r) => ({
      key: r.key,
      label: r.label,
      valence: r.valence as Valence,
      groupKey: r.group_key,
    }));
  }

  /** The same vocabulary nested, which is the shape both clients actually render. */
  findGroups(): FeelingGroup[] {
    const rows = this.db
      .prepare('SELECT "key", label, valence FROM feeling_groups ORDER BY sort_order, "key"')
      .all() as Array<{ key: string; label: string; valence: string }>;

    const byGroup = new Map<string, Feeling[]>();
    for (const feeling of this.findAll()) {
      const existing = byGroup.get(feeling.groupKey);
      if (existing) existing.push(feeling);
      else byGroup.set(feeling.groupKey, [feeling]);
    }

    // A group with nothing in it is dropped rather than served empty: a client would render a
    // chip that opens onto nothing.
    return rows
      .map((r) => ({
        key: r.key,
        label: r.label,
        valence: r.valence as Valence,
        feelings: byGroup.get(r.key) ?? [],
      }))
      .filter((group) => group.feelings.length > 0);
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
