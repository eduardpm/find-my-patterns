import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import {
  InvalidAudioError,
  TranscriptionService,
  TranscriptionUnavailableError,
} from './transcription.service';
import { EntriesService } from '../entries/entries.service';
import { TRANSCRIPT_FORMATTING, type TranscriptFormatting } from '../inference/inference';

export type TranscriptionJob =
  | { status: 'pending' }
  | { status: 'completed'; transcript: string }
  | { status: 'failed'; error: string };

/** A stored job, plus the owner `find` checks before ever handing the result back. */
type OwnedJob = TranscriptionJob & { userId: string };

const RESULT_RETENTION_MS = 15 * 60 * 1000;

/**
 * Keeps the HTTP request short while whisper.cpp works. This matters through reverse proxies that
 * cap request duration. Results are deliberately ephemeral: the client turns a completed result
 * into a normal guided answer, which is the durable database record.
 *
 * This in-memory `jobs` map carries no `user_id` column to check — it is not one of
 * `USER_DATA_TABLES` and `ScopedDb`'s guard never sees it (M-1b, #46) — so ownership is asserted by
 * hand here instead: every job is stored with the `userId` that started it, and `find` refuses to
 * hand a job back to anyone else. A job id is an unguessable random UUID, but "unguessable" is not
 * the same guarantee as "scoped" — a raw, not-yet-saved transcript is exactly the kind of content
 * this ticket exists to keep from crossing accounts, ephemeral or not.
 */
@Injectable()
export class TranscriptionJobsService {
  private readonly jobs = new Map<string, OwnedJob>();

  constructor(
    private readonly transcription: TranscriptionService,
    private readonly entries: EntriesService,
    @Inject(TRANSCRIPT_FORMATTING) private readonly formatting: TranscriptFormatting,
  ) {}

  start(
    userId: string,
    audio: Buffer,
    destination?: { entryId: string; questionKey: string; orderIndex: number },
  ): string {
    const id = randomUUID();
    this.jobs.set(id, { status: 'pending', userId });
    void this.transcription
      .transcribe(audio)
      .then(async (transcript) => {
        if (destination) {
          // Save verbatim speech first. Formatting is enhancement, never the durability boundary.
          this.entries.saveGuidedDraftAnswer(
            userId,
            destination.entryId,
            destination.questionKey,
            transcript,
            destination.orderIndex,
          );
          const formatted = await this.formatting.formatTranscript(
            userId,
            destination.entryId,
            transcript,
          );
          this.entries.saveGuidedDraftAnswer(
            userId,
            destination.entryId,
            destination.questionKey,
            formatted,
            destination.orderIndex,
          );
          transcript = formatted;
        }
        this.jobs.set(id, { status: 'completed', transcript, userId });
      })
      .catch((error: unknown) => {
        const message =
          error instanceof InvalidAudioError || error instanceof TranscriptionUnavailableError
            ? error.message
            : 'Local speech-to-text failed. Please try again.';
        this.jobs.set(id, { status: 'failed', error: message, userId });
      })
      .finally(() => {
        const timer = setTimeout(() => this.jobs.delete(id), RESULT_RETENTION_MS);
        timer.unref();
      });
    return id;
  }

  /** `undefined` both when the job is gone and when it belongs to a different user — the same
   * answer a caller cannot tell apart, which is the point: a 404 either way, never a hint that a
   * job id it guessed at belongs to somebody else. */
  find(userId: string, id: string): TranscriptionJob | undefined {
    const job = this.jobs.get(id);
    if (!job || job.userId !== userId) return undefined;
    // Rebuilt rather than returning `job` as-is: `TranscriptionJob` is the documented wire shape,
    // and a caller (or a test asserting `toEqual`) must never see the internal ownership marker
    // leak into it.
    if (job.status === 'completed') return { status: 'completed', transcript: job.transcript };
    if (job.status === 'failed') return { status: 'failed', error: job.error };
    return { status: 'pending' };
  }
}
