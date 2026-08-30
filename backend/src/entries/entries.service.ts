import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { decodeDate, encodeDate, encodeDateTime, nowUtc, todayLocal } from '../db/codecs';
import type { NaiveDateTime, PlainDate } from '../db/codecs';
import { SCOPED_DB, type ScopedDb } from '../db/scoped-db';
import type {
  DiaryEntry,
  EntryOrigin,
  SuggestedFeeling,
  TopicFeelingPairing,
} from '../domain/types';
import { ENTRY_INFERENCE, type EntryInference } from '../inference/inference';
import { StaleEntryError } from '../common/stale-entry';
import { daysBetween } from '../insights/analysis';
import { CONFIRMED_FEELING_SOURCES } from '../insights/constants';
import { EntriesRepository } from './entries.repository';
import { GUIDED_DRAFT_SENTINEL } from './guided-draft';

export class EntryNotFoundError extends Error {}
export class GuidedDraftNotFoundError extends Error {}
export class EmptyGuidedDraftError extends Error {}
/** A pairing write named a topic or feeling that is not on this entry — 422 (E-1a). */
export class InvalidPairingError extends Error {}
/** `entry_date` names a future day, or one too far in the past — 422 (#36). */
export class InvalidEntryDateError extends Error {}

/** How far back `entry_date` may backdate an entry (#36, daylio-competitive-analysis.md §11.6). */
export const MAX_BACKDATE_DAYS = 30;

export interface TopicFeelingPairingInput {
  topicId: string;
  feelingKey: string;
}

export interface GuidedAnswerInput {
  question_key: string;
  answer_text: string;
}

export interface EntryCreateInput {
  mode: 'guided' | 'freeform';
  raw_text: string;
  guided_answers: GuidedAnswerInput[];
  /** Backdates the entry (#36). Omitted files it under the server's own `todayLocal()`. */
  entry_date?: string;
}

/**
 * An already-parsed, already-mapped external row, ready to become a stored entry (L-1b, #35).
 * `feelingKey` must already be a validated member of `FEELING_KEYS` — mapping and "skip and
 * report the unmapped ones" both happen upstream, in the importer itself, never here.
 */
export interface ImportedEntryInput {
  rawText: string;
  entryDate: PlainDate;
  /** The moment the source app recorded this entry, exactly as its own export stated it. */
  createdAt: NaiveDateTime;
  feelingKey: string;
  origin: EntryOrigin;
}

export interface EntryUpdateInput {
  raw_text?: string | null;
  /** Legacy single-feeling form. Treated as a one-element `feeling_keys`. */
  feeling_key?: string | null;
  feeling_keys?: string[] | null;
  /** Legacy single-value form. Read as a rating of the primary feeling (I6-03). */
  feeling_intensity?: number | null;
  /** One optional rating per feeling. Absent leaves the stored ratings alone; a map replaces them. */
  feeling_intensities?: Record<string, number> | null;
  version: number;
}

@Injectable()
export class EntriesService {
  constructor(
    @Inject(SCOPED_DB) private readonly db: ScopedDb,
    private readonly repo: EntriesRepository,
    @Inject(ENTRY_INFERENCE) private readonly inference: EntryInference,
  ) {}

  /**
   * Create an entry, then enqueue local analysis without holding the HTTP response open.
   *
   * Two subtleties are ported exactly and both are visible in stored data:
   *
   *  - **Guided composition.** `raw_text` is built as one block per answer — the prompt on its own
   *    line, the answer under it, blocks separated by a blank line — and only when no `raw_text`
   *    was submitted. `question_text_snapshot` is the question's prompt, falling back to the raw
   *    key when the question is unknown — and that same fallback appears in the composed text
   *    (data-model.md "Derived values").
   *  - **Two writes.** The entry is stored first, then the worker updates it later, so the entry
   *    survives even if local inference is unavailable. The API process never connects to Ollama
   *    and never waits for it.
   */
  createEntry(
    userId: string,
    data: EntryCreateInput,
  ): {
    entry: DiaryEntry;
    suggestion: SuggestedFeeling | null;
  } {
    // Resolved and validated before anything else is written — a rejected `entry_date` must leave
    // no trace, the same "whole request or nothing" rule the rest of this service follows.
    const entryDate = data.entry_date
      ? encodeDate(this.resolveBackdate(data.entry_date))
      : encodeDate(todayLocal());

    let text = data.raw_text ?? '';
    const guidedRows: Array<{
      id: string;
      questionKey: string;
      snapshot: string;
      answerText: string;
      orderIndex: number;
    }> = [];

    const handle = this.db.forUser(userId);

    if (data.mode === 'guided' && data.guided_answers?.length) {
      // `guiding_questions` is shared reference vocabulary (`schema.ts`'s M-1b note), not user
      // data — no `user_id` column exists on it, so this read is intentionally not routed through
      // `handle`, matching `FeelingsRepository`/`GuidingQuestionsRepository`'s own choice to stay on
      // the raw `DiaryDatabase`. `ScopedDb`'s guard never inspects this statement either way, since
      // it names no table in `USER_DATA_TABLES`.
      const questions = new Map(
        (
          handle.prepare('SELECT "key", prompt_text FROM guiding_questions').all() as Array<{
            key: string;
            prompt_text: string;
          }>
        ).map((q) => [q.key, q.prompt_text]),
      );

      const rendered: string[] = [];
      data.guided_answers.forEach((answer, index) => {
        const prompt = questions.get(answer.question_key) ?? answer.question_key;
        guidedRows.push({
          id: randomUUID(),
          questionKey: answer.question_key,
          snapshot: prompt,
          answerText: answer.answer_text,
          orderIndex: index,
        });
        rendered.push(`${prompt}\n${answer.answer_text.trim()}`);
      });

      // Each answer is its own block, prompt on its own line above it, blocks separated by a blank
      // line. This used to be `"{prompt} {answer}"` joined by single spaces, which ran three
      // questions and three answers together into one unbroken paragraph that nobody could read
      // back — least of all the person who wrote it, who had to find their own words inside the
      // app's. The stored text is what every client shows and what the analyser reads, and
      // paragraph breaks change nothing about the second while fixing the first.
      if (!text) text = rendered.join('\n\n');
    }

    const id = randomUUID();
    const created = encodeDateTime(nowUtc());

    handle.transaction(() => {
      handle
        .prepare(
          `INSERT INTO diary_entries
           (id, user_id, created_at, updated_at, entry_date, mode, raw_text, feeling_key,
            feeling_source, version)
           VALUES (?, ?, ?, ?, ?, ?, ?, NULL, 'unset', 1)`,
        )
        .run(id, userId, created, created, entryDate, data.mode, text);

      const insertAnswer = handle.prepare(
        `INSERT INTO guiding_question_answers
         (id, user_id, entry_id, question_key, question_text_snapshot, answer_text, order_index)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      );
      for (const row of guidedRows) {
        insertAnswer.run(
          row.id,
          userId,
          id,
          row.questionKey,
          row.snapshot,
          row.answerText,
          row.orderIndex,
        );
      }
    });

    const suggestion = text.trim() ? this.analyzeStoredEntry(userId, id) : null;

    return { entry: this.repo.findById(userId, id)!, suggestion };
  }

  /**
   * Create an entry from an already-parsed, already-mapped external row (L-1b, #35) — the Daylio
   * CSV importer's write path, and the only other producer of `diary_entries` rows besides
   * `createEntry`.
   *
   * Three ways this deliberately diverges from `createEntry`:
   *
   *  - **No inference is enqueued.** The feeling did not come from a suggestion the user might
   *    confirm — it was read straight off the CSV and conservatively mapped
   *    (`import/daylio-mood-map.ts`) — so there is nothing left for the local analyser to propose.
   *    Enqueuing it anyway would queue one job per imported entry (thousands, for years of
   *    history) for no benefit: `analyzeStoredEntry` only ever writes while
   *    `feeling_source = 'unset'`, and this method never leaves it there.
   *  - **`feeling_source` is written as `'overridden'` from the first insert**, never `'unset'`
   *    then `'suggested'`. `improvement-opportunities.md` §8 is explicit that an import must mark
   *    entries so "nothing is silently treated as evidence the user didn't see" — `'overridden'`
   *    is the vocabulary's strongest marker for "a person's own words, not a model's guess", which
   *    is what a Daylio mood rating is. Note the consequence stated in the PR description:
   *    `CONFIRMED_FEELING_SOURCES` includes `'overridden'`, so these entries *do* count as pattern
   *    evidence — that is this ticket's intended behaviour, not an oversight.
   *  - **No [MAX_BACKDATE_DAYS] limit.** That cap exists for *manual* backdating (#36) — "I forgot
   *    to write for a few days" — and years of imported history is exactly what it would reject.
   *    Only "not in the future" is enforced here; the 30-day floor is not this method's business.
   */
  createImportedEntry(userId: string, input: ImportedEntryInput): DiaryEntry {
    const age = daysBetween(input.entryDate, todayLocal());
    if (age < 0) {
      throw new InvalidEntryDateError('Entry date cannot be in the future.');
    }

    const id = randomUUID();
    const createdAt = encodeDateTime(input.createdAt);
    const handle = this.db.forUser(userId);

    handle.transaction(() => {
      handle
        .prepare(
          `INSERT INTO diary_entries
           (id, user_id, created_at, updated_at, entry_date, mode, raw_text, feeling_key,
            feeling_source, version, origin)
           VALUES (?, ?, ?, ?, ?, 'freeform', ?, ?, 'overridden', 1, ?)`,
        )
        .run(
          id,
          userId,
          createdAt,
          // `updated_at` mirrors `created_at`: nothing has touched this row's content since the
          // moment it describes, and that moment is the historical one from the CSV — not the
          // moment the import job happened to run.
          createdAt,
          encodeDate(input.entryDate),
          input.rawText,
          input.feelingKey,
          input.origin,
        );
      this.replaceFeelings(userId, id, [input.feelingKey]);
    });

    return this.repo.findById(userId, id)!;
  }

  /**
   * Validates an explicit `entry_date` against the server's own `todayLocal()` (#36): a diary
   * entry can be backdated to help patterns surface sooner, but never postdated, and only within
   * [MAX_BACKDATE_DAYS] — far enough to cover "I forgot to write for a few days", not so far that
   * the date picker becomes a way to fabricate a diary's history.
   *
   * `data.entry_date`'s shape (`YYYY-MM-DD`) is already guaranteed by `entryCreateSchema`; this is
   * the one place — mirroring every other date field in this codebase — where it is actually
   * parsed and checked against the calendar.
   */
  private resolveBackdate(raw: string): PlainDate {
    const parsed = decodeDate(raw);
    const age = daysBetween(parsed, todayLocal());
    if (age < 0) {
      throw new InvalidEntryDateError('Entry date cannot be in the future.');
    }
    if (age > MAX_BACKDATE_DAYS) {
      throw new InvalidEntryDateError(
        `Entry date cannot be more than ${MAX_BACKDATE_DAYS} days in the past.`,
      );
    }
    return parsed;
  }

  /**
   * Write an entry's whole feeling set, and its primary feeling with it.
   *
   * `entry_feelings` is the truth and `diary_entries.feeling_key` is the first element of it. They
   * are written in one place — here — precisely so nothing can set one without the other. Callers
   * must already be inside a transaction.
   */
  private replaceFeelings(
    userId: string,
    entryId: string,
    keys: string[],
    intensities: Record<string, number | null> = {},
  ): void {
    // De-duplicated while preserving order: the set is a set, and `entry_feelings` has a composite
    // primary key that a repeated word would collide with.
    const ordered = [...new Set(keys)];
    const handle = this.db.forUser(userId);
    handle
      .prepare('DELETE FROM entry_feelings WHERE user_id = ? AND entry_id = ?')
      .run(userId, entryId);
    const insert = handle.prepare(
      `INSERT INTO entry_feelings (entry_id, user_id, feeling_key, position, intensity)
       VALUES (?, ?, ?, ?, ?)`,
    );
    // A rating for a feeling that is not on the entry is dropped rather than stored: the map is
    // read through the set, never beside it, so the two cannot drift apart.
    ordered.forEach((key, position) =>
      insert.run(entryId, userId, key, position, intensities[key] ?? null),
    );
  }

  /** Begin a guided entry before the first answer so every subsequent PUT is independently safe. */
  createGuidedDraft(userId: string): string {
    const handle = this.db.forUser(userId);
    const existing = handle
      .prepare(
        'SELECT id FROM diary_entries WHERE user_id = ? AND raw_text = ? ORDER BY created_at DESC, id DESC LIMIT 1',
      )
      .get(userId, GUIDED_DRAFT_SENTINEL) as { id: string } | undefined;
    if (existing) return existing.id;

    const id = randomUUID();
    const created = encodeDateTime(nowUtc());
    handle
      .prepare(
        `INSERT INTO diary_entries
         (id, user_id, created_at, updated_at, entry_date, mode, raw_text, feeling_key,
          feeling_source, version)
         VALUES (?, ?, ?, ?, ?, 'guided', ?, NULL, 'unset', 1)`,
      )
      .run(id, userId, created, created, encodeDate(todayLocal()), GUIDED_DRAFT_SENTINEL);
    return id;
  }

  getGuidedDraft(userId: string, entryId: string): { answers: GuidedAnswerInput[] } {
    this.assertGuidedDraft(userId, entryId);
    return {
      answers: this.repo.findGuidedAnswers(userId, entryId).map((answer) => ({
        question_key: answer.questionKey,
        answer_text: answer.answerText,
      })),
    };
  }

  /** PUT semantics: retrying the same question replaces its answer instead of duplicating it. */
  saveGuidedDraftAnswer(
    userId: string,
    entryId: string,
    questionKey: string,
    answerText: string,
    orderIndex: number,
  ): void {
    const handle = this.db.forUser(userId);
    handle.transaction(() => {
      this.assertGuidedDraft(userId, entryId);
      // `guiding_questions` is shared reference vocabulary — see `createEntry`'s note on the same
      // read above for why it is not filtered by `user_id`.
      const question = handle
        .prepare('SELECT prompt_text FROM guiding_questions WHERE "key" = ?')
        .get(questionKey) as { prompt_text: string } | undefined;
      const existing = handle
        .prepare(
          'SELECT id FROM guiding_question_answers WHERE user_id = ? AND entry_id = ? AND question_key = ?',
        )
        .get(userId, entryId, questionKey) as { id: string } | undefined;

      if (existing) {
        handle
          .prepare(
            `UPDATE guiding_question_answers SET answer_text = ?, order_index = ?,
             question_text_snapshot = ? WHERE id = ? AND user_id = ?`,
          )
          .run(answerText, orderIndex, question?.prompt_text ?? questionKey, existing.id, userId);
      } else {
        handle
          .prepare(
            `INSERT INTO guiding_question_answers
             (id, user_id, entry_id, question_key, question_text_snapshot, answer_text, order_index)
             VALUES (?, ?, ?, ?, ?, ?, ?)`,
          )
          .run(
            randomUUID(),
            userId,
            entryId,
            questionKey,
            question?.prompt_text ?? questionKey,
            answerText,
            orderIndex,
          );
      }
      handle
        .prepare('UPDATE diary_entries SET updated_at = ? WHERE id = ? AND user_id = ?')
        .run(encodeDateTime(nowUtc()), entryId, userId);
    });
  }

  finalizeGuidedDraft(
    userId: string,
    entryId: string,
  ): {
    entry: DiaryEntry;
    suggestion: SuggestedFeeling | null;
  } {
    this.assertGuidedDraft(userId, entryId);
    const answers = this.repo.findGuidedAnswers(userId, entryId);
    if (answers.length === 0) throw new EmptyGuidedDraftError('Draft has no answers');
    const text = answers
      .map((answer) => `${answer.questionTextSnapshot} ${answer.answerText}`)
      .join(' ');
    this.db
      .forUser(userId)
      .prepare('UPDATE diary_entries SET raw_text = ?, updated_at = ? WHERE id = ? AND user_id = ?')
      .run(text, encodeDateTime(nowUtc()), entryId, userId);
    const suggestion = this.analyzeStoredEntry(userId, entryId);
    return { entry: this.repo.findById(userId, entryId)!, suggestion };
  }

  deleteGuidedDraft(userId: string, entryId: string): void {
    const handle = this.db.forUser(userId);
    handle.transaction(() => {
      this.assertGuidedDraft(userId, entryId);
      handle
        .prepare('DELETE FROM guiding_question_answers WHERE user_id = ? AND entry_id = ?')
        .run(userId, entryId);
      handle
        .prepare('DELETE FROM entry_feelings WHERE user_id = ? AND entry_id = ?')
        .run(userId, entryId);
      handle
        .prepare('DELETE FROM inference_jobs WHERE user_id = ? AND entry_id = ?')
        .run(userId, entryId);
      handle.prepare('DELETE FROM diary_entries WHERE id = ? AND user_id = ?').run(entryId, userId);
    });
  }

  private assertGuidedDraft(userId: string, entryId: string): void {
    const row = this.db
      .forUser(userId)
      .prepare('SELECT raw_text FROM diary_entries WHERE id = ? AND user_id = ?')
      .get(entryId, userId) as { raw_text: string } | undefined;
    if (!row || row.raw_text !== GUIDED_DRAFT_SENTINEL) {
      throw new GuidedDraftNotFoundError(entryId);
    }
  }

  /**
   * The analyser's current opinion of an entry, and whether it is still forming one.
   *
   * `suggested` is non-null unless a *user* has already spoken for the same feelings the analyser
   * is proposing. Agreement alone is not enough to suppress: the worker applies its own answer
   * straight onto the entry (`feeling_source = 'suggested'`) before this ever runs, so for a
   * freshly analysed entry the entry's feelings and the analyser's proposal are *always* identical
   * -- suppressing on identity alone silently threw away every suggestion the moment it was
   * created (#66). The guard is only about not re-nagging a real choice: once the entry's source is
   * `'confirmed'` or `'overridden'`, a client showing "we suggest: happy" under a feeling the user
   * already confirmed as happy is noise, and that is the only case this suppresses.
   */
  analysisFor(
    userId: string,
    entryId: string,
  ): {
    suggested: SuggestedFeeling | null;
    suggestedAll: SuggestedFeeling[];
    pending: boolean;
  } {
    const handle = this.db.forUser(userId);
    const pending =
      (handle
        .prepare(
          `SELECT 1 FROM inference_jobs
           WHERE user_id = ? AND entry_id = ? AND kind = 'entry_analysis'
             AND status IN ('queued', 'running')
           LIMIT 1`,
        )
        .get(userId, entryId) as unknown) !== undefined;
    const nothing = { suggested: null, suggestedAll: [], pending };

    const done = handle
      .prepare(
        `SELECT result_json FROM inference_jobs
         WHERE user_id = ? AND entry_id = ? AND kind = 'entry_analysis' AND status = 'completed'
           AND result_json IS NOT NULL
         ORDER BY completed_at DESC LIMIT 1`,
      )
      .get(userId, entryId) as { result_json: string } | undefined;

    if (!done) return nothing;

    let parsed: { feeling_key?: unknown; confidence?: unknown; feelings?: unknown };
    try {
      parsed = JSON.parse(done.result_json) as typeof parsed;
    } catch {
      return nothing;
    }

    const suggestions = readSuggestedFeelings(parsed);
    if (suggestions.length === 0) return nothing;

    const entry = this.repo.findById(userId, entryId);
    if (!entry) return nothing;

    // Nothing to propose when a *user* has already chosen exactly what the analyser is proposing
    // — a client showing "we suggest: happy" under a feeling the user confirmed as happy is
    // noise. With a set, agreement means the same feelings, regardless of the order they were
    // written in. Agreement while the source is still `'suggested'` (or `'unset'`) is not that
    // case — it is the analyser's own write agreeing with itself, which is the normal state of a
    // freshly analysed entry and exactly what the client needs surfaced to pre-select from.
    const current = new Set(entry.feelingKeys);
    const proposed = suggestions.map((suggestion) => suggestion.key);
    const identical = current.size === proposed.length && proposed.every((key) => current.has(key));
    const userAlreadyChose = (CONFIRMED_FEELING_SOURCES as readonly string[]).includes(
      entry.feelingSource,
    );
    if (identical && userAlreadyChose) return nothing;

    return { suggested: suggestions[0], suggestedAll: suggestions, pending };
  }

  private analyzeStoredEntry(userId: string, entryId: string): SuggestedFeeling | null {
    const analysis = this.inference.enqueueEntry(userId, entryId);
    if (!analysis || analysis.feelings.length === 0) return null;
    // Normally the worker has already applied this. The idempotent write keeps tests deterministic.
    const handle = this.db.forUser(userId);
    return handle.transaction(() => {
      const applied = handle
        .prepare(
          `UPDATE diary_entries SET feeling_key = ?, feeling_source = 'suggested', updated_at = ?
           WHERE id = ? AND user_id = ? AND feeling_source = 'unset'`,
        )
        .run(analysis.feelings[0].key, encodeDateTime(nowUtc()), entryId, userId);
      if (applied.changes === 1) {
        this.replaceFeelings(
          userId,
          entryId,
          analysis.feelings.map((suggestion) => suggestion.key),
        );
      }
      return analysis.feelings[0];
    });
  }

  /**
   * Apply an edit, but only if the client's view is current (FR-011).
   *
   * The check happens before anything is written and the whole thing runs in one transaction: a
   * rejected write must be a complete no-op, or FR-023's "never silently pick a winner" is violated
   * by a half-applied edit.
   */
  updateEntry(userId: string, entryId: string, data: EntryUpdateInput): DiaryEntry {
    const handle = this.db.forUser(userId);
    return handle.transaction(() => {
      const entry = this.repo.findById(userId, entryId);
      if (!entry) throw new EntryNotFoundError(entryId);
      if (entry.version !== data.version) throw new StaleEntryError(entry);

      let rawText = entry.rawText;
      if (data.raw_text !== undefined && data.raw_text !== null) rawText = data.raw_text;

      // `feeling_keys` is the current form; `feeling_key` is the single-feeling one older clients
      // send, and means a set of exactly one. An empty list is not "clear the feeling" — it is a
      // client sending nothing, and is ignored, the same way an absent field always was.
      const requested = data.feeling_keys ?? (data.feeling_key != null ? [data.feeling_key] : null);
      const chosen = requested ? [...new Set(requested)] : null;

      let feelingKey = entry.feelingKey;
      let feelingSource = entry.feelingSource;
      if (chosen && chosen.length > 0) {
        // Compared against the *previously suggested* set, and only while the source is still
        // 'suggested' — confirming what was proposed differs from overriding it. Compared as a
        // set, because re-ordering the same feelings is not an override.
        const previouslySuggested =
          entry.feelingSource === 'suggested' ? new Set(entry.feelingKeys) : null;
        feelingKey = chosen[0];
        feelingSource =
          previouslySuggested !== null &&
          previouslySuggested.size === chosen.length &&
          chosen.every((key) => previouslySuggested.has(key))
            ? 'confirmed'
            : 'overridden';
      }

      const textChanged = rawText !== entry.rawText;

      // Intensity belongs to the feeling it was set on (I6-03), which is now literally true: the
      // ratings travel keyed by feeling, so an edit that reorders or removes feelings can no
      // longer slide a "4" off *anxious* and onto *calm*. Whatever the user rated keeps its
      // rating; a feeling dropped from the entry takes its rating with it.
      //
      // `feeling_intensities` sent explicitly wins. Left out, the stored ratings survive, filtered
      // to the feelings that are still on the entry. `feeling_intensity` (the single-value form an
      // older client sends) is read as a rating of the primary feeling, so those clients keep
      // working unchanged.
      const finalKeys = chosen && chosen.length > 0 ? chosen : entry.feelingKeys;
      let ratings: Record<string, number | null>;
      if (data.feeling_intensities !== undefined && data.feeling_intensities !== null) {
        ratings = { ...data.feeling_intensities };
      } else {
        ratings = { ...entry.feelingIntensities };
        if (data.feeling_intensity !== undefined) {
          // No primary feeling to hang it on means there is nothing to record.
          if (feelingKey) ratings[feelingKey] = data.feeling_intensity;
        }
      }
      // Ratings only exist for feelings the entry still carries.
      ratings = Object.fromEntries(
        Object.entries(ratings).filter(([key, value]) => finalKeys.includes(key) && value != null),
      );

      // The denormalised column mirrors the primary feeling's rating and nothing else, so the
      // calendar and older clients keep reading a number that is true about the dot they draw.
      const intensity = feelingKey ? (ratings[feelingKey] ?? null) : null;

      handle
        .prepare(
          `UPDATE diary_entries SET raw_text = ?, feeling_key = ?, feeling_source = ?,
           feeling_intensity = ?, updated_at = ?, version = version + 1
           WHERE id = ? AND user_id = ?`,
        )
        .run(
          rawText,
          feelingKey,
          feelingSource,
          intensity,
          encodeDateTime(nowUtc()),
          entryId,
          userId,
        );

      // Rewritten even when the feelings themselves did not change, because an intensity-only
      // edit — the user rating a second feeling on an entry they already wrote — changes nothing
      // else and must still be stored.
      if (finalKeys.length > 0) this.replaceFeelings(userId, entryId, finalKeys, ratings);

      // Edited text is different text: the topics extracted from the old wording no longer describe
      // this entry, and leaving them in place quietly poisons pattern detection with words the
      // entry no longer contains. So the links are dropped and the entry goes back through the
      // pipeline. A feeling-only edit changes nothing the analyser reads, so it is left alone.
      if (textChanged && rawText.trim()) {
        handle
          .prepare('DELETE FROM entry_topics WHERE user_id = ? AND entry_id = ?')
          .run(userId, entryId);
        // A pairing is a claim about *this wording* of the entry — once the topics it named are
        // gone, a stored pairing (suggested or confirmed alike) no longer describes anything real,
        // the same reasoning that drops `entry_topics` here.
        handle
          .prepare('DELETE FROM entry_topic_feelings WHERE user_id = ? AND entry_id = ?')
          .run(userId, entryId);
        handle
          .prepare(
            `DELETE FROM inference_jobs WHERE user_id = ? AND entry_id = ? AND kind = 'entry_analysis'`,
          )
          .run(userId, entryId);
        this.inference.enqueueEntry(userId, entryId);
      }

      return this.repo.findById(userId, entryId)!;
    });
  }

  /**
   * FR-021: a stale delete is the most destructive thing the manual-refresh model allows.
   *
   * Children are removed explicitly. SQLite only honours `ON DELETE CASCADE` when
   * `PRAGMA foreign_keys` is on, and that is deliberately off (see database.ts) — so without these
   * statements the diary would accumulate orphaned answers and topic links that inflate counts.
   */
  deleteEntry(userId: string, entryId: string, version: number): void {
    const handle = this.db.forUser(userId);
    handle.transaction(() => {
      const entry = this.repo.findById(userId, entryId);
      if (!entry) throw new EntryNotFoundError(entryId);
      if (entry.version !== version) throw new StaleEntryError(entry);

      handle
        .prepare('DELETE FROM guiding_question_answers WHERE user_id = ? AND entry_id = ?')
        .run(userId, entryId);
      handle
        .prepare('DELETE FROM entry_feelings WHERE user_id = ? AND entry_id = ?')
        .run(userId, entryId);
      handle
        .prepare('DELETE FROM entry_topics WHERE user_id = ? AND entry_id = ?')
        .run(userId, entryId);
      handle
        .prepare('DELETE FROM entry_topic_feelings WHERE user_id = ? AND entry_id = ?')
        .run(userId, entryId);
      handle
        .prepare('DELETE FROM pattern_entries WHERE user_id = ? AND entry_id = ?')
        .run(userId, entryId);
      handle
        .prepare('DELETE FROM inference_jobs WHERE user_id = ? AND entry_id = ?')
        .run(userId, entryId);
      handle.prepare('DELETE FROM diary_entries WHERE id = ? AND user_id = ?').run(entryId, userId);
      // Scoped to this user's own topics only — a topic another user still references (through
      // their own `entry_topics`/`patterns` rows) must never be considered for cleanup here; this
      // user deleting their last entry that named "work" must not touch a different account's own
      // "work" topic (a distinct row since `schema.ts`'s M-1b step 2: `topics.name` is unique per
      // user, not globally).
      handle
        .prepare(
          `DELETE FROM topics WHERE user_id = ?
           AND id NOT IN (SELECT topic_id FROM entry_topics WHERE user_id = ?)
           AND id NOT IN (SELECT topic_id FROM patterns WHERE user_id = ?)`,
        )
        .run(userId, userId, userId);
    });
  }

  /**
   * Store the user's confirmed/overridden topic↔feeling pairings for an entry, replacing whatever
   * was there before (E-1a).
   *
   * Validated against the entry's *own* topics and feelings only — a pairing naming a topic this
   * entry never mentioned, or a feeling that is not on it, is rejected outright rather than
   * silently dropped, the same "whole request or nothing" rule `updateEntry` applies to
   * `feeling_keys`.
   *
   * `source` is never taken from the request; it is derived here, mirroring how `updateEntry`
   * derives `feeling_source` — a pair that matches what the worker last *suggested* is
   * `'confirmed'`, and anything else the user submits is `'overridden'`. The comparison is
   * per-pair, not per-entry: a mixed-valence entry can confirm one pairing and override another in
   * the same call.
   */
  setTopicFeelingPairings(
    userId: string,
    entryId: string,
    pairs: TopicFeelingPairingInput[],
  ): TopicFeelingPairing[] {
    const handle = this.db.forUser(userId);
    return handle.transaction(() => {
      const entry = this.repo.findById(userId, entryId);
      if (!entry) throw new EntryNotFoundError(entryId);

      const validTopicIds = new Set(this.repo.entryTopicIds(userId, entryId));
      const validFeelingKeys = new Set(entry.feelingKeys);
      for (const pair of pairs) {
        if (!validTopicIds.has(pair.topicId)) {
          throw new InvalidPairingError(`Topic is not on this entry: ${pair.topicId}`);
        }
        if (!validFeelingKeys.has(pair.feelingKey)) {
          throw new InvalidPairingError(`Feeling is not on this entry: ${pair.feelingKey}`);
        }
      }

      // A set of pairs has no order and no repeats — de-duplicated the same way `replaceFeelings`
      // de-duplicates a feeling set, keyed on the pair rather than a single string.
      const deduped = new Map<string, TopicFeelingPairingInput>();
      for (const pair of pairs) deduped.set(`${pair.topicId} ${pair.feelingKey}`, pair);

      const previouslySuggested = new Set(
        (
          handle
            .prepare(
              `SELECT topic_id, feeling_key FROM entry_topic_feelings
               WHERE user_id = ? AND entry_id = ? AND source = 'suggested'`,
            )
            .all(userId, entryId) as Array<{ topic_id: string; feeling_key: string }>
        ).map((row) => `${row.topic_id} ${row.feeling_key}`),
      );

      handle
        .prepare('DELETE FROM entry_topic_feelings WHERE user_id = ? AND entry_id = ?')
        .run(userId, entryId);
      const insert = handle.prepare(
        `INSERT INTO entry_topic_feelings (entry_id, topic_id, feeling_key, user_id, source)
         VALUES (?, ?, ?, ?, ?)`,
      );
      for (const [key, pair] of deduped) {
        const source = previouslySuggested.has(key) ? 'confirmed' : 'overridden';
        insert.run(entryId, pair.topicId, pair.feelingKey, userId, source);
      }

      return this.repo.findTopicFeelingPairings(userId, entryId);
    });
  }
}

/**
 * Read the analyser's suggestion out of a stored job result.
 *
 * Handles both shapes deliberately: the current one carries a `feelings` array, and a diary that
 * was analysed before the vocabulary grew has completed jobs holding a single `feeling_key`. A
 * stored result is data written by an earlier version of this code, so it is parsed defensively
 * rather than trusted.
 */
function readSuggestedFeelings(parsed: {
  feeling_key?: unknown;
  confidence?: unknown;
  feelings?: unknown;
}): SuggestedFeeling[] {
  if (Array.isArray(parsed.feelings)) {
    const suggestions: SuggestedFeeling[] = [];
    for (const item of parsed.feelings) {
      if (typeof item !== 'object' || item === null) continue;
      const { key, confidence } = item as { key?: unknown; confidence?: unknown };
      if (typeof key !== 'string' || !key) continue;
      suggestions.push({ key, confidence: typeof confidence === 'number' ? confidence : 0 });
    }
    if (suggestions.length > 0) return suggestions;
  }

  if (typeof parsed.feeling_key === 'string' && parsed.feeling_key) {
    return [
      {
        key: parsed.feeling_key,
        confidence: typeof parsed.confidence === 'number' ? parsed.confidence : 0,
      },
    ];
  }
  return [];
}
