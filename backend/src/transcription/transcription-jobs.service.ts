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

const RESULT_RETENTION_MS = 15 * 60 * 1000;

/**
 * Keeps the HTTP request short while whisper.cpp works. This matters through reverse proxies that
 * cap request duration. Results are deliberately ephemeral: the client turns a completed result
 * into a normal guided answer, which is the durable database record.
 */
@Injectable()
export class TranscriptionJobsService {
  private readonly jobs = new Map<string, TranscriptionJob>();

  constructor(
    private readonly transcription: TranscriptionService,
    private readonly entries: EntriesService,
    @Inject(TRANSCRIPT_FORMATTING) private readonly formatting: TranscriptFormatting,
  ) {}

  start(
    audio: Buffer,
    destination?: { entryId: string; questionKey: string; orderIndex: number },
  ): string {
    const id = randomUUID();
    this.jobs.set(id, { status: 'pending' });
    void this.transcription
      .transcribe(audio)
      .then(async (transcript) => {
        if (destination) {
          // Save verbatim speech first. Formatting is enhancement, never the durability boundary.
          this.entries.saveGuidedDraftAnswer(
            destination.entryId,
            destination.questionKey,
            transcript,
            destination.orderIndex,
          );
          const formatted = await this.formatting.formatTranscript(destination.entryId, transcript);
          this.entries.saveGuidedDraftAnswer(
            destination.entryId,
            destination.questionKey,
            formatted,
            destination.orderIndex,
          );
          transcript = formatted;
        }
        this.jobs.set(id, { status: 'completed', transcript });
      })
      .catch((error: unknown) => {
        const message =
          error instanceof InvalidAudioError || error instanceof TranscriptionUnavailableError
            ? error.message
            : 'Local speech-to-text failed. Please try again.';
        this.jobs.set(id, { status: 'failed', error: message });
      })
      .finally(() => {
        const timer = setTimeout(() => this.jobs.delete(id), RESULT_RETENTION_MS);
        timer.unref();
      });
    return id;
  }

  find(id: string): TranscriptionJob | undefined {
    return this.jobs.get(id);
  }
}
