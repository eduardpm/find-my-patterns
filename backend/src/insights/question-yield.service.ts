import { Inject, Injectable } from '@nestjs/common';
import { decodeJson } from '../db/codecs';
import { SCOPED_DB, type ScopedDb } from '../db/scoped-db';
import { GUIDED_DRAFT_SENTINEL } from '../entries/guided-draft';
import { mentions } from '../topics/canonicalization';

/** One optional bound of the measurement window, `entry_date` inclusive, `YYYY-MM-DD`. */
export interface QuestionYieldRange {
  from?: string;
  to?: string;
}

export interface QuestionYieldRow {
  question_key: string;
  /**
   * The most recent `question_text_snapshot` recorded against this key within the window — the
   * wording a reader actually saw, not `guiding_questions.prompt_text` (which is only ever the
   * *current* wording and would silently relabel every past answer if the copy has since changed).
   * "Most recent" is by the answer's entry `created_at`, so a mid-window copy change (UX-8a)
   * surfaces here immediately.
   */
  wording_snapshot_latest: string;
  /** Guided entries that answered this question at least once in the window. */
  answered: number;
  /** Of those, entries whose answer to this question is attributed at least one topic. */
  yielded: number;
  /** `yielded / answered`, or `null` when nothing answered this question in the window. */
  rate: number | null;
}

export interface QuestionYieldOverall {
  /** Guided (non-draft) entries in the window. */
  guided_entries: number;
  /** Of those, entries carrying at least one linked topic — the SC-008 numerator. */
  guided_entries_yielding: number;
  /** SC-008: the target is ≥0.9. `null` when the window has no guided entries. */
  rate: number | null;
}

export interface QuestionYieldReport {
  from: string | null;
  to: string | null;
  overall: QuestionYieldOverall;
  questions: QuestionYieldRow[];
}

interface AnswerRow {
  entry_id: string;
  entry_created_at: string;
  question_key: string;
  question_text_snapshot: string;
  answer_text: string;
}

interface EntryTopicRow {
  entry_id: string;
  name: string;
  aliases: string;
}

interface CountRow {
  cnt: number;
}

interface QuestionAccumulator {
  wording: string;
  answered: Set<string>;
  yielded: Set<string>;
}

/**
 * SC-008 measurement: does a guided answer earn its keep?
 *
 * Guided questions exist to produce extractable topics — that is the product's framing for them,
 * not an incidental side effect — so a question that answers reliably but never yields a topic is
 * failing at its one job even though nothing about it looks broken. This service is the only place
 * that number is computed.
 *
 * ## Attribution rule
 *
 * `entry_topics` links a topic to the **entry**, not to the guided answer that produced it —
 * that is the only granularity the schema records, because topic extraction (`topics.service.ts`)
 * always runs over an entry's whole `raw_text`. To attribute a topic back to one answer among
 * several on the same entry, an answer is credited with a topic when that topic's canonical name
 * or one of its recorded aliases appears as a whole word/phrase inside the *answer's own text* —
 * the same `mentions()` match the keyword extractor itself uses (`topics/canonicalization.ts`),
 * applied here per-answer instead of per-entry.
 *
 * This is a stated approximation, not a precise derivation:
 *  - a topic mentioned in two answers on the same entry credits both, because stored data cannot
 *    say which answer the extractor actually used and crediting neither would undercount as badly
 *    as crediting both overcounts;
 *  - a topic linked to the entry via free text the client appended outside the guided answers (an
 *    edge case `raw_text` allows) can credit an answer that never mentioned it, for the same
 *    reason — the entry is the only place `entry_topics` looks;
 *  - only topics *currently* linked to the entry are considered, so editing an entry's text after
 *    the fact changes its yield the next time patterns are recomputed (`entry_topics` is derived,
 *    recomputed data — see `PatternsService.recomputePatterns`), not retroactively per answer.
 *
 * Also documented in `backend/docs/question-yield.md` per the ticket's requirement that the rule
 * be stated, not merely implemented.
 *
 * Unfinalized guided drafts (`raw_text === GUIDED_DRAFT_SENTINEL`) are excluded throughout, the
 * same way `EntriesRepository` excludes them — a draft is not yet an entry the user kept.
 */
@Injectable()
export class QuestionYieldService {
  constructor(@Inject(SCOPED_DB) private readonly db: ScopedDb) {}

  compute(userId: string, range: QuestionYieldRange): QuestionYieldReport {
    const handle = this.db.forUser(userId);
    const { clause, params } = whereClause(userId, range);

    const totalRow = handle
      .prepare(`SELECT COUNT(*) AS cnt FROM diary_entries e WHERE ${clause}`)
      .get(...params) as CountRow;

    const yieldingRow = handle
      .prepare(
        `SELECT COUNT(DISTINCT e.id) AS cnt
         FROM diary_entries e
         JOIN entry_topics et ON et.entry_id = e.id
         WHERE ${clause}`,
      )
      .get(...params) as CountRow;

    const topicRows = handle
      .prepare(
        `SELECT e.id AS entry_id, t.name AS name, t.aliases AS aliases
         FROM diary_entries e
         JOIN entry_topics et ON et.entry_id = e.id
         JOIN topics t ON t.id = et.topic_id
         WHERE ${clause}`,
      )
      .all(...params) as EntryTopicRow[];

    const surfaceFormsByEntry = new Map<string, string[]>();
    for (const row of topicRows) {
      const forms = [row.name, ...decodeJson<string[]>(row.aliases ?? '[]')];
      const existing = surfaceFormsByEntry.get(row.entry_id);
      if (existing) existing.push(...forms);
      else surfaceFormsByEntry.set(row.entry_id, forms);
    }

    // Oldest first, so — per question key — the last row processed carries the most recent
    // snapshot, and that is what ends up stored as `wording_snapshot_latest`.
    const answerRows = handle
      .prepare(
        `SELECT e.id AS entry_id, e.created_at AS entry_created_at, a.question_key AS question_key,
                a.question_text_snapshot AS question_text_snapshot, a.answer_text AS answer_text
         FROM diary_entries e
         JOIN guiding_question_answers a ON a.entry_id = e.id
         WHERE ${clause}
         ORDER BY e.created_at ASC, e.id ASC, a.order_index ASC`,
      )
      .all(...params) as AnswerRow[];

    const byQuestion = new Map<string, QuestionAccumulator>();
    for (const row of answerRows) {
      let acc = byQuestion.get(row.question_key);
      if (!acc) {
        acc = { wording: row.question_text_snapshot, answered: new Set(), yielded: new Set() };
        byQuestion.set(row.question_key, acc);
      }
      acc.wording = row.question_text_snapshot;
      acc.answered.add(row.entry_id);

      const forms = surfaceFormsByEntry.get(row.entry_id) ?? [];
      const text = row.answer_text.toLowerCase();
      if (forms.some((form) => form.trim() && mentions(text, form.toLowerCase()))) {
        acc.yielded.add(row.entry_id);
      }
    }

    const questions: QuestionYieldRow[] = [...byQuestion.entries()]
      .map(([question_key, acc]) => ({
        question_key,
        wording_snapshot_latest: acc.wording,
        answered: acc.answered.size,
        yielded: acc.yielded.size,
        rate: acc.answered.size > 0 ? acc.yielded.size / acc.answered.size : null,
      }))
      .sort((a, b) => a.question_key.localeCompare(b.question_key));

    const guidedEntries = totalRow.cnt;
    const guidedEntriesYielding = yieldingRow.cnt;

    return {
      from: range.from ?? null,
      to: range.to ?? null,
      overall: {
        guided_entries: guidedEntries,
        guided_entries_yielding: guidedEntriesYielding,
        rate: guidedEntries > 0 ? guidedEntriesYielding / guidedEntries : null,
      },
      questions,
    };
  }
}

function whereClause(
  userId: string,
  range: QuestionYieldRange,
): { clause: string; params: string[] } {
  const clauses = ['e.user_id = ?', `e.mode = 'guided'`, 'e.raw_text <> ?'];
  const params: string[] = [userId, GUIDED_DRAFT_SENTINEL];
  if (range.from) {
    clauses.push('e.entry_date >= ?');
    params.push(range.from);
  }
  if (range.to) {
    clauses.push('e.entry_date <= ?');
    params.push(range.to);
  }
  return { clause: clauses.join(' AND '), params };
}
