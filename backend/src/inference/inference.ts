import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { loadConfig } from '../config';
import { encodeDateTime, nowUtc } from '../db/codecs';
import { SCOPED_DB, type ScopedDb } from '../db/scoped-db';
import type { SuggestedFeeling } from '../domain/types';

/**
 * Re-exported so the request validator and the model's output schema keep reading the vocabulary
 * from the one place that defines it (`db/feeling-vocabulary.ts`), rather than from a second list
 * here that would drift the first time a feeling is added.
 */
export { FEELING_KEYS, FEELING_GROUP_KEYS } from '../db/feeling-vocabulary';

/**
 * One topic↔feeling pairing the analyser proposed for an entry (E-1a), before it is resolved to a
 * stored topic id. `topic` names an entry of {@link EntryAnalysis.topics} exactly — the caller
 * that applies the analysis is what maps a proposed topic phrase onto its canonical, persisted
 * topic row. `feelingKeys` is always a subset of the entry's own proposed feelings: the whole
 * point of aspect-based extraction is *which of the feelings already found* a topic goes with, not
 * a second, independent guess.
 */
export interface ProposedPairing {
  topic: string;
  feelingKeys: string[];
}

export interface EntryAnalysis {
  /**
   * Every feeling the analyser found in the text, strongest first — an entry about a hard day
   * that ended well is genuinely two feelings, and forcing it to one throws away the half the
   * user would most want to see later. The first element is the entry's primary feeling.
   */
  feelings: SuggestedFeeling[];
  topics: string[];
  /**
   * For each topic above that the text clearly ties to one or more of `feelings`, that pairing
   * (E-1a). A topic with no clear feeling association is simply absent here — "no pairing" is a
   * normal, common answer, not a gap to fill in.
   */
  pairings: ProposedPairing[];
}

export interface EntryInference {
  /** Enqueue analysis and return without waiting for the worker. */
  enqueueEntry(userId: string, entryId: string): EntryAnalysis | null;
}

export const ENTRY_INFERENCE = Symbol('ENTRY_INFERENCE');
export const TRANSCRIPT_FORMATTING = Symbol('TRANSCRIPT_FORMATTING');

export interface TranscriptFormatting {
  formatTranscript(userId: string, entryId: string, transcript: string): Promise<string>;
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
  constructor(@Inject(SCOPED_DB) private readonly db: ScopedDb) {}

  enqueueEntry(userId: string, entryId: string): null {
    const id = randomUUID();
    this.db
      .forUser(userId)
      .prepare(
        `INSERT INTO inference_jobs
         (id, user_id, kind, entry_id, status, result_json, error_text, attempts, created_at,
          started_at, completed_at)
         VALUES (?, ?, 'entry_analysis', ?, 'queued', NULL, NULL, 0, ?, NULL, NULL)`,
      )
      .run(id, userId, entryId, encodeDateTime(nowUtc()));
    return null;
  }
}

/** Uses the same durable worker boundary as feeling extraction; raw text remains the fallback. */
@Injectable()
export class QueuedTranscriptFormatting implements TranscriptFormatting {
  private readonly waitMs = loadConfig().transcriptFormattingWaitMs;

  constructor(@Inject(SCOPED_DB) private readonly db: ScopedDb) {}

  async formatTranscript(userId: string, entryId: string, transcript: string): Promise<string> {
    const id = randomUUID();
    const handle = this.db.forUser(userId);
    handle
      .prepare(
        `INSERT INTO inference_jobs
         (id, user_id, kind, entry_id, status, result_json, error_text, attempts, created_at,
          started_at, completed_at)
         VALUES (?, ?, 'transcript_format', ?, 'queued', ?, NULL, 0, ?, NULL, NULL)`,
      )
      .run(id, userId, entryId, JSON.stringify({ input: transcript }), encodeDateTime(nowUtc()));

    const deadline = Date.now() + this.waitMs;
    for (;;) {
      const job = handle
        .prepare('SELECT status, result_json FROM inference_jobs WHERE id = ? AND user_id = ?')
        .get(id, userId) as JobRow | undefined;
      if (!job) return transcript;
      if (job.status === 'failed') {
        handle.prepare('DELETE FROM inference_jobs WHERE id = ? AND user_id = ?').run(id, userId);
        return transcript;
      }
      if (job.status === 'completed') {
        handle.prepare('DELETE FROM inference_jobs WHERE id = ? AND user_id = ?').run(id, userId);
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
    return { feelings: [{ key: 'neutral', confidence: 0 }], topics: [], pairings: [] };
  }
}

export class ImmediateTestTranscriptFormatting implements TranscriptFormatting {
  async formatTranscript(_userId: string, _entryId: string, transcript: string): Promise<string> {
    return transcript;
  }
}
