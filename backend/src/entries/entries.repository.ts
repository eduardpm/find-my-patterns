import { Inject, Injectable } from '@nestjs/common';
import { decodeBool, decodeDate, decodeDateTime, decodeJson, encodeDate } from '../db/codecs';
import { DIARY_DB } from '../db/database.provider';
import { SCOPED_DB, type ScopedDb } from '../db/scoped-db';
import type { DiaryDatabase } from '../db/database';
import type {
  DiaryEntry,
  EntryMode,
  EntryOrigin,
  Feeling,
  FeelingGroup,
  FeelingSource,
  GuidedAnswer,
  GuidingQuestion,
  PairingSource,
  TopicFeelingPairing,
  Valence,
} from '../domain/types';
import type { PlainDate } from '../db/codecs';
import type { Topic } from '../topics/topics.service';
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
  origin: string;
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
    origin: row.origin as EntryOrigin,
  };
}

@Injectable()
export class EntriesRepository {
  constructor(@Inject(SCOPED_DB) private readonly db: ScopedDb) {}

  /**
   * The feeling sets for a batch of entries, in one query.
   *
   * Per-entry lookups would be simpler to write and are the reason list endpoints quietly become
   * N+1 queries; a day or a month of entries is read in one go everywhere else in this class, and
   * their feelings are read the same way.
   *
   * `entryIds` are always this same `userId`'s own — every caller sources them from a query already
   * filtered by `user_id` (`hydrate`'s own callers) — but the `WHERE user_id = ?` here is not
   * redundant with that: it is what makes this statement itself, read on its own, an honest
   * per-user query rather than one that only happens to be safe because of what called it.
   */
  private feelingKeysFor(userId: string, entryIds: string[]): Map<string, FeelingSet> {
    const byEntry = new Map<string, FeelingSet>();
    if (entryIds.length === 0) return byEntry;
    const rows = this.db
      .forUser(userId)
      .prepare(
        `SELECT entry_id, feeling_key, intensity FROM entry_feelings
         WHERE user_id = ? AND entry_id IN (${entryIds.map(() => '?').join(', ')})
         ORDER BY entry_id, position, feeling_key`,
      )
      .all(userId, ...entryIds) as Array<{
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

  private hydrate(userId: string, rows: EntryRow[]): DiaryEntry[] {
    const feelings = this.feelingKeysFor(
      userId,
      rows.map((row) => row.id),
    );
    return rows.map((row) => {
      const set = feelings.get(row.id);
      return toEntry(row, set?.keys ?? [], set?.intensities ?? {});
    });
  }

  findByDate(userId: string, date: PlainDate): DiaryEntry[] {
    // Ordered by created_at — User Story 1's acceptance criteria.
    const rows = this.db
      .forUser(userId)
      .prepare<EntryRow>(
        'SELECT * FROM diary_entries WHERE user_id = ? AND entry_date = ? AND raw_text <> ? ORDER BY created_at',
      )
      .all(userId, encodeDate(date), GUIDED_DRAFT_SENTINEL) as EntryRow[];
    return this.hydrate(userId, rows);
  }

  findById(userId: string, id: string): DiaryEntry | null {
    const row = this.db
      .forUser(userId)
      .prepare<EntryRow>(
        'SELECT * FROM diary_entries WHERE id = ? AND user_id = ? AND raw_text <> ?',
      )
      .get(id, userId, GUIDED_DRAFT_SENTINEL) as EntryRow | undefined;
    return row ? this.hydrate(userId, [row])[0] : null;
  }

  findAll(userId: string): DiaryEntry[] {
    const rows = this.db
      .forUser(userId)
      .prepare<EntryRow>(
        'SELECT * FROM diary_entries WHERE user_id = ? AND raw_text <> ? ORDER BY created_at',
      )
      .all(userId, GUIDED_DRAFT_SENTINEL) as EntryRow[];
    return this.hydrate(userId, rows);
  }

  findInDateRange(userId: string, start: PlainDate, end: PlainDate): DiaryEntry[] {
    const rows = this.db
      .forUser(userId)
      .prepare<EntryRow>(
        `SELECT * FROM diary_entries
         WHERE user_id = ? AND entry_date >= ? AND entry_date <= ? AND raw_text <> ?
         ORDER BY created_at`,
      )
      .all(userId, encodeDate(start), encodeDate(end), GUIDED_DRAFT_SENTINEL) as EntryRow[];
    return this.hydrate(userId, rows);
  }

  findGuidedAnswers(userId: string, entryId: string): GuidedAnswer[] {
    const rows = this.db
      .forUser(userId)
      .prepare(
        'SELECT * FROM guiding_question_answers WHERE user_id = ? AND entry_id = ? ORDER BY order_index',
      )
      .all(userId, entryId) as Array<{
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

  /**
   * The entry's topic↔feeling pairings (E-1a), joined out to the topic's name. Ordered for a
   * stable, deterministic wire shape rather than SQLite's insertion order.
   *
   * `topic` is still carried here even though the entry payload also serves `topics` directly
   * (#81, via `TopicsService.topicsForEntry()`): a pairing row's own topic name is what makes each
   * pairing self-describing without a client having to cross-reference the two lists.
   *
   * Filtered on `etf.user_id` — the join's own owning table — rather than `t.user_id`: both are
   * always the same value for a real row (a pairing can only ever name a topic its own owner also
   * owns), but filtering the table actually being selected from is what the `ScopedDb` guard is
   * checking for, and it is also the filter that costs nothing extra should that assumption ever
   * become false.
   */
  findTopicFeelingPairings(userId: string, entryId: string): TopicFeelingPairing[] {
    const rows = this.db
      .forUser(userId)
      .prepare(
        `SELECT etf.topic_id, t.name AS topic, etf.feeling_key, etf.source
         FROM entry_topic_feelings etf JOIN topics t ON t.id = etf.topic_id
         WHERE etf.user_id = ? AND etf.entry_id = ? ORDER BY t.name, etf.feeling_key`,
      )
      .all(userId, entryId) as Array<{
      topic_id: string;
      topic: string;
      feeling_key: string;
      source: string;
    }>;
    return rows.map((r) => ({
      topicId: r.topic_id,
      topic: r.topic,
      feelingKey: r.feeling_key,
      source: r.source as PairingSource,
    }));
  }

  /**
   * The canonical topics linked to an entry — an entry serves no topics of its own on any other
   * read endpoint, so the export controller (M-6) reaches for this the same way
   * `findTopicFeelingPairings` above does. Ordered by name for a stable, deterministic wire shape.
   *
   * `entry_topics` carries no per-entry surface form — only which canonical topic row a mention
   * resolved to (`docs/export.md` "Topics" explains why the export repeats the canonical name for
   * both fields rather than inventing one).
   */
  findTopics(userId: string, entryId: string): Topic[] {
    const rows = this.db
      .forUser(userId)
      .prepare(
        `SELECT t.id, t.name FROM entry_topics et JOIN topics t ON t.id = et.topic_id
         WHERE et.user_id = ? AND et.entry_id = ? ORDER BY t.name`,
      )
      .all(userId, entryId) as Array<{ id: string; name: string }>;
    return rows.map((r) => ({ id: r.id, name: r.name }));
  }

  /** The topic ids currently linked to an entry — the set a pairing write is validated against. */
  entryTopicIds(userId: string, entryId: string): string[] {
    return (
      this.db
        .forUser(userId)
        .prepare('SELECT topic_id FROM entry_topics WHERE user_id = ? AND entry_id = ?')
        .all(userId, entryId) as Array<{
        topic_id: string;
      }>
    ).map((r) => r.topic_id);
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
