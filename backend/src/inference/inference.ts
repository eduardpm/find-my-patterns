import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { loadConfig } from '../config';
import { encodeDateTime, nowUtc } from '../db/codecs';
import { DIARY_DB } from '../db/database.provider';
import type { DiaryDatabase } from '../db/database';
import type { SuggestedFeeling } from '../domain/types';

/**
 * Re-exported so the request validator and the model's output schema keep reading the vocabulary
 * from the one place that defines it (`db/feeling-vocabulary.ts`), rather than from a second list
 * here that would drift the first time a feeling is added.
 */
export { FEELING_KEYS, FEELING_GROUP_KEYS } from '../db/feeling-vocabulary';

export interface EntryAnalysis {
  /**
   * Every feeling the analyser found in the text, strongest first — an entry about a hard day
   * that ended well is genuinely two feelings, and forcing it to one throws away the half the
   * user would most want to see later. The first element is the entry's primary feeling.
   */
  feelings: SuggestedFeeling[];
  topics: string[];
}

export interface EntryInference {
  /** Enqueue analysis and return without waiting for the worker. */
  enqueueEntry(entryId: string): EntryAnalysis | null;
}

export const ENTRY_INFERENCE = Symbol('ENTRY_INFERENCE');
export const TRANSCRIPT_FORMATTING = Symbol('TRANSCRIPT_FORMATTING');

export interface TranscriptFormatting {
  formatTranscript(entryId: string, transcript: string): Promise<string>;
}

interface JobRow {
  status: string;
  result_json: string | null;
}

const delay = (milliseconds: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

/**
 * API-side half of the inference boundary. It only writes SQLite jobs; the API process never
 * connects to Ollama, loads a model, or waits for a result.
 */
@Injectable()
export class QueuedEntryInference implements EntryInference {
  constructor(@Inject(DIARY_DB) private readonly db: DiaryDatabase) {}

  enqueueEntry(entryId: string): null {
    const id = randomUUID();
    this.db
      .prepare(
        `INSERT INTO inference_jobs
         (id, kind, entry_id, status, result_json, error_text, attempts, created_at,
          started_at, completed_at)
         VALUES (?, 'entry_analysis', ?, 'queued', NULL, NULL, 0, ?, NULL, NULL)`,
      )
      .run(id, entryId, encodeDateTime(nowUtc()));
    return null;
  }
}

/** Uses the same durable worker boundary as feeling extraction; raw text remains the fallback. */
@Injectable()
export class QueuedTranscriptFormatting implements TranscriptFormatting {
  private readonly waitMs = loadConfig().transcriptFormattingWaitMs;

  constructor(@Inject(DIARY_DB) private readonly db: DiaryDatabase) {}

  async formatTranscript(entryId: string, transcript: string): Promise<string> {
    const id = randomUUID();
    this.db
      .prepare(
        `INSERT INTO inference_jobs
         (id, kind, entry_id, status, result_json, error_text, attempts, created_at,
          started_at, completed_at)
         VALUES (?, 'transcript_format', ?, 'queued', ?, NULL, 0, ?, NULL, NULL)`,
      )
      .run(id, entryId, JSON.stringify({ input: transcript }), encodeDateTime(nowUtc()));

    const deadline = Date.now() + this.waitMs;
    for (;;) {
      const job = this.db
        .prepare('SELECT status, result_json FROM inference_jobs WHERE id = ?')
        .get(id) as JobRow | undefined;
      if (!job) return transcript;
      if (job.status === 'failed') {
        this.db.prepare('DELETE FROM inference_jobs WHERE id = ?').run(id);
        return transcript;
      }
      if (job.status === 'completed') {
        this.db.prepare('DELETE FROM inference_jobs WHERE id = ?').run(id);
        if (!job.result_json) return transcript;
        const result = JSON.parse(job.result_json) as { text?: unknown };
        return typeof result.text === 'string' ? result.text : transcript;
      }
      if (Date.now() >= deadline) return transcript;
      await delay(100);
    }
  }
}

/** Test-only contract double: production always uses the durable queue above. */
export class ImmediateTestInference implements EntryInference {
  enqueueEntry(): EntryAnalysis {
    return { feelings: [{ key: 'neutral', confidence: 0 }], topics: [] };
  }
}

export class ImmediateTestTranscriptFormatting implements TranscriptFormatting {
  async formatTranscript(_entryId: string, transcript: string): Promise<string> {
    return transcript;
  }
}
