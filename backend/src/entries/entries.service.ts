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
  feeling_key?: string | null;
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
   *  - **Guided composition.** `raw_text` is built as `"{prompt} {answer}"` per answer joined by a
   *    single space, and only when no `raw_text` was submitted. `question_text_snapshot` is the
   *    question's prompt, falling back to the raw key when the question is unknown — and that same
   *    fallback appears in the composed text (data-model.md "Derived values").
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
        rendered.push(`${prompt} ${answer.answer_text}`);
      });

      if (!text) text = rendered.join(' ');
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

  private analyzeStoredEntry(entryId: string): SuggestedFeeling | null {
    const analysis = this.inference.enqueueEntry(entryId);
    if (!analysis) return null;
    const suggestion = analysis.feeling;
    // Normally the worker has already applied this. The idempotent write keeps tests deterministic.
    this.db
      .prepare(
        `UPDATE diary_entries SET feeling_key = ?, feeling_source = 'suggested', updated_at = ?
         WHERE id = ? AND feeling_source = 'unset'`,
      )
      .run(suggestion.key, encodeDateTime(nowUtc()), entryId);
    return suggestion;
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

      let feelingKey = entry.feelingKey;
      let feelingSource = entry.feelingSource;
      if (data.feeling_key !== undefined && data.feeling_key !== null) {
        // Compared against the *previously suggested* value, and only while the source is still
        // 'suggested' — confirming what was proposed differs from overriding it.
        const previouslySuggested = entry.feelingSource === 'suggested' ? entry.feelingKey : null;
        feelingKey = data.feeling_key;
        feelingSource =
          previouslySuggested !== null && previouslySuggested === data.feeling_key
            ? 'confirmed'
            : 'overridden';
      }

      this.db
        .prepare(
          `UPDATE diary_entries SET raw_text = ?, feeling_key = ?, feeling_source = ?,
           updated_at = ?, version = version + 1 WHERE id = ?`,
        )
        .run(rawText, feelingKey, feelingSource, encodeDateTime(nowUtc()), entryId);

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
