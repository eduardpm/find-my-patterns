import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { encodeDate, encodeDateTime, nowUtc, todayLocal } from '../db/codecs';
import { DIARY_DB } from '../db/database.provider';
import type { DiaryDatabase } from '../db/database';
import type { DiaryEntry, SuggestedFeeling } from '../domain/types';
import { ENTRY_INFERENCE, type EntryInference } from '../inference/inference';
import { StaleEntryError } from '../common/stale-entry';
import { EntriesRepository } from './entries.repository';
import { GUIDED_DRAFT_SENTINEL } from './guided-draft';

export class EntryNotFoundError extends Error {}
export class GuidedDraftNotFoundError extends Error {}
export class EmptyGuidedDraftError extends Error {}

export interface GuidedAnswerInput {
  question_key: string;
  answer_text: string;
}

export interface EntryCreateInput {
  mode: 'guided' | 'freeform';
  raw_text: string;
  guided_answers: GuidedAnswerInput[];
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
    @Inject(DIARY_DB) private readonly db: DiaryDatabase,
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
  createEntry(data: EntryCreateInput): {
    entry: DiaryEntry;
    suggestion: SuggestedFeeling | null;
  } {
    let text = data.raw_text ?? '';
    const guidedRows: Array<{
      id: string;
      questionKey: string;
      snapshot: string;
      answerText: string;
      orderIndex: number;
    }> = [];

    if (data.mode === 'guided' && data.guided_answers?.length) {
      const questions = new Map(
        (
          this.db.prepare('SELECT "key", prompt_text FROM guiding_questions').all() as Array<{
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

    this.db.transaction(() => {
      this.db
        .prepare(
          `INSERT INTO diary_entries
           (id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source, version)
           VALUES (?, ?, ?, ?, ?, ?, NULL, 'unset', 1)`,
        )
        .run(id, created, created, encodeDate(todayLocal()), data.mode, text);

      const insertAnswer = this.db.prepare(
        `INSERT INTO guiding_question_answers
         (id, entry_id, question_key, question_text_snapshot, answer_text, order_index)
         VALUES (?, ?, ?, ?, ?, ?)`,
      );
      for (const row of guidedRows) {
        insertAnswer.run(row.id, id, row.questionKey, row.snapshot, row.answerText, row.orderIndex);
      }
    });

    const suggestion = text.trim() ? this.analyzeStoredEntry(id) : null;

    return { entry: this.repo.findById(id)!, suggestion };
  }

  /**
   * Write an entry's whole feeling set, and its primary feeling with it.
   *
   * `entry_feelings` is the truth and `diary_entries.feeling_key` is the first element of it. They
   * are written in one place — here — precisely so nothing can set one without the other. Callers
   * must already be inside a transaction.
   */
  private replaceFeelings(
    entryId: string,
    keys: string[],
    intensities: Record<string, number | null> = {},
  ): void {
    // De-duplicated while preserving order: the set is a set, and `entry_feelings` has a composite
    // primary key that a repeated word would collide with.
    const ordered = [...new Set(keys)];
    this.db.prepare('DELETE FROM entry_feelings WHERE entry_id = ?').run(entryId);
    const insert = this.db.prepare(
      'INSERT INTO entry_feelings (entry_id, feeling_key, position, intensity) VALUES (?, ?, ?, ?)',
    );
    // A rating for a feeling that is not on the entry is dropped rather than stored: the map is
    // read through the set, never beside it, so the two cannot drift apart.
    ordered.forEach((key, position) =>
      insert.run(entryId, key, position, intensities[key] ?? null),
    );
  }

  /** Begin a guided entry before the first answer so every subsequent PUT is independently safe. */
  createGuidedDraft(): string {
    const existing = this.db
      .prepare(
        'SELECT id FROM diary_entries WHERE raw_text = ? ORDER BY created_at DESC, id DESC LIMIT 1',
      )
      .get(GUIDED_DRAFT_SENTINEL) as { id: string } | undefined;
    if (existing) return existing.id;

    const id = randomUUID();
    const created = encodeDateTime(nowUtc());
    this.db
      .prepare(
        `INSERT INTO diary_entries
         (id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source, version)
         VALUES (?, ?, ?, ?, 'guided', ?, NULL, 'unset', 1)`,
      )
      .run(id, created, created, encodeDate(todayLocal()), GUIDED_DRAFT_SENTINEL);
    return id;
  }

  getGuidedDraft(entryId: string): { answers: GuidedAnswerInput[] } {
    this.assertGuidedDraft(entryId);
    return {
      answers: this.repo.findGuidedAnswers(entryId).map((answer) => ({
        question_key: answer.questionKey,
        answer_text: answer.answerText,
      })),
    };
  }

  /** PUT semantics: retrying the same question replaces its answer instead of duplicating it. */
  saveGuidedDraftAnswer(
    entryId: string,
    questionKey: string,
    answerText: string,
    orderIndex: number,
  ): void {
    this.db.transaction(() => {
      this.assertGuidedDraft(entryId);
      const question = this.db
        .prepare('SELECT prompt_text FROM guiding_questions WHERE "key" = ?')
        .get(questionKey) as { prompt_text: string } | undefined;
      const existing = this.db
        .prepare('SELECT id FROM guiding_question_answers WHERE entry_id = ? AND question_key = ?')
        .get(entryId, questionKey) as { id: string } | undefined;

      if (existing) {
        this.db
          .prepare(
            `UPDATE guiding_question_answers SET answer_text = ?, order_index = ?,
             question_text_snapshot = ? WHERE id = ?`,
          )
          .run(answerText, orderIndex, question?.prompt_text ?? questionKey, existing.id);
      } else {
        this.db
          .prepare(
            `INSERT INTO guiding_question_answers
             (id, entry_id, question_key, question_text_snapshot, answer_text, order_index)
             VALUES (?, ?, ?, ?, ?, ?)`,
          )
          .run(
            randomUUID(),
            entryId,
            questionKey,
            question?.prompt_text ?? questionKey,
            answerText,
            orderIndex,
          );
      }
      this.db
        .prepare('UPDATE diary_entries SET updated_at = ? WHERE id = ?')
        .run(encodeDateTime(nowUtc()), entryId);
    });
  }

  finalizeGuidedDraft(entryId: string): {
    entry: DiaryEntry;
    suggestion: SuggestedFeeling | null;
  } {
    this.assertGuidedDraft(entryId);
    const answers = this.repo.findGuidedAnswers(entryId);
    if (answers.length === 0) throw new EmptyGuidedDraftError('Draft has no answers');
    const text = answers
      .map((answer) => `${answer.questionTextSnapshot} ${answer.answerText}`)
      .join(' ');
    this.db
      .prepare('UPDATE diary_entries SET raw_text = ?, updated_at = ? WHERE id = ?')
      .run(text, encodeDateTime(nowUtc()), entryId);
    const suggestion = this.analyzeStoredEntry(entryId);
    return { entry: this.repo.findById(entryId)!, suggestion };
  }

  deleteGuidedDraft(entryId: string): void {
    this.db.transaction(() => {
      this.assertGuidedDraft(entryId);
      this.db.prepare('DELETE FROM guiding_question_answers WHERE entry_id = ?').run(entryId);
      this.db.prepare('DELETE FROM entry_feelings WHERE entry_id = ?').run(entryId);
      this.db.prepare('DELETE FROM inference_jobs WHERE entry_id = ?').run(entryId);
      this.db.prepare('DELETE FROM diary_entries WHERE id = ?').run(entryId);
    });
  }

  private assertGuidedDraft(entryId: string): void {
    const row = this.db.prepare('SELECT raw_text FROM diary_entries WHERE id = ?').get(entryId) as
      { raw_text: string } | undefined;
    if (!row || row.raw_text !== GUIDED_DRAFT_SENTINEL) {
      throw new GuidedDraftNotFoundError(entryId);
    }
  }

  /**
   * The analyser's current opinion of an entry, and whether it is still forming one.
   *
   * `suggested` is non-null only when the analyser's latest answer *differs* from the feeling the
   * entry actually carries -- there is nothing to propose when they already agree, and a client
   * showing "we suggest: happy" under a feeling that is already happy is noise.
   */
  analysisFor(entryId: string): {
    suggested: SuggestedFeeling | null;
    suggestedAll: SuggestedFeeling[];
    pending: boolean;
  } {
    const pending =
      (this.db
        .prepare(
          `SELECT 1 FROM inference_jobs
           WHERE entry_id = ? AND kind = 'entry_analysis' AND status IN ('queued', 'running')
           LIMIT 1`,
        )
        .get(entryId) as unknown) !== undefined;
    const nothing = { suggested: null, suggestedAll: [], pending };

    const done = this.db
      .prepare(
        `SELECT result_json FROM inference_jobs
         WHERE entry_id = ? AND kind = 'entry_analysis' AND status = 'completed'
           AND result_json IS NOT NULL
         ORDER BY completed_at DESC LIMIT 1`,
      )
      .get(entryId) as { result_json: string } | undefined;

    if (!done) return nothing;

    let parsed: { feeling_key?: unknown; confidence?: unknown; feelings?: unknown };
    try {
      parsed = JSON.parse(done.result_json) as typeof parsed;
    } catch {
      return nothing;
    }

    const suggestions = readSuggestedFeelings(parsed);
    if (suggestions.length === 0) return nothing;

    const entry = this.repo.findById(entryId);
    if (!entry) return nothing;

    // Nothing to propose when the analyser and the entry already agree — a client showing
    // "we suggest: happy" under a feeling that is already happy is noise. With a set, agreement
    // means the same feelings, regardless of the order they were written in.
    const current = new Set(entry.feelingKeys);
    const proposed = suggestions.map((suggestion) => suggestion.key);
    const identical = current.size === proposed.length && proposed.every((key) => current.has(key));
    if (identical) return nothing;

    return { suggested: suggestions[0], suggestedAll: suggestions, pending };
  }

  private analyzeStoredEntry(entryId: string): SuggestedFeeling | null {
    const analysis = this.inference.enqueueEntry(entryId);
    if (!analysis || analysis.feelings.length === 0) return null;
    // Normally the worker has already applied this. The idempotent write keeps tests deterministic.
    return this.db.transaction(() => {
      const applied = this.db
        .prepare(
          `UPDATE diary_entries SET feeling_key = ?, feeling_source = 'suggested', updated_at = ?
           WHERE id = ? AND feeling_source = 'unset'`,
        )
        .run(analysis.feelings[0].key, encodeDateTime(nowUtc()), entryId);
      if (applied.changes === 1) {
        this.replaceFeelings(
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
  updateEntry(entryId: string, data: EntryUpdateInput): DiaryEntry {
    return this.db.transaction(() => {
      const entry = this.repo.findById(entryId);
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

      this.db
        .prepare(
          `UPDATE diary_entries SET raw_text = ?, feeling_key = ?, feeling_source = ?,
           feeling_intensity = ?, updated_at = ?, version = version + 1 WHERE id = ?`,
        )
        .run(rawText, feelingKey, feelingSource, intensity, encodeDateTime(nowUtc()), entryId);

      // Rewritten even when the feelings themselves did not change, because an intensity-only
      // edit — the user rating a second feeling on an entry they already wrote — changes nothing
      // else and must still be stored.
      if (finalKeys.length > 0) this.replaceFeelings(entryId, finalKeys, ratings);

      // Edited text is different text: the topics extracted from the old wording no longer describe
      // this entry, and leaving them in place quietly poisons pattern detection with words the
      // entry no longer contains. So the links are dropped and the entry goes back through the
      // pipeline. A feeling-only edit changes nothing the analyser reads, so it is left alone.
      if (textChanged && rawText.trim()) {
        this.db.prepare('DELETE FROM entry_topics WHERE entry_id = ?').run(entryId);
        this.db
          .prepare(`DELETE FROM inference_jobs WHERE entry_id = ? AND kind = 'entry_analysis'`)
          .run(entryId);
        this.inference.enqueueEntry(entryId);
      }

      return this.repo.findById(entryId)!;
    });
  }

  /**
   * FR-021: a stale delete is the most destructive thing the manual-refresh model allows.
   *
   * Children are removed explicitly. SQLite only honours `ON DELETE CASCADE` when
   * `PRAGMA foreign_keys` is on, and that is deliberately off (see database.ts) — so without these
   * statements the diary would accumulate orphaned answers and topic links that inflate counts.
   */
  deleteEntry(entryId: string, version: number): void {
    this.db.transaction(() => {
      const entry = this.repo.findById(entryId);
      if (!entry) throw new EntryNotFoundError(entryId);
      if (entry.version !== version) throw new StaleEntryError(entry);

      this.db.prepare('DELETE FROM guiding_question_answers WHERE entry_id = ?').run(entryId);
      this.db.prepare('DELETE FROM entry_feelings WHERE entry_id = ?').run(entryId);
      this.db.prepare('DELETE FROM entry_topics WHERE entry_id = ?').run(entryId);
      this.db.prepare('DELETE FROM pattern_entries WHERE entry_id = ?').run(entryId);
      this.db.prepare('DELETE FROM inference_jobs WHERE entry_id = ?').run(entryId);
      this.db.prepare('DELETE FROM diary_entries WHERE id = ?').run(entryId);
      this.db
        .prepare(
          `DELETE FROM topics WHERE id NOT IN (SELECT topic_id FROM entry_topics)
           AND id NOT IN (SELECT topic_id FROM patterns)`,
        )
        .run();
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
