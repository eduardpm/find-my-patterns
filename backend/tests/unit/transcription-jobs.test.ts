import { describe, expect, it, vi } from 'vitest';
import { TranscriptionJobsService } from '../../src/transcription/transcription-jobs.service';
import type { TranscriptionService } from '../../src/transcription/transcription.service';
import type { EntriesService } from '../../src/entries/entries.service';
import type { TranscriptFormatting } from '../../src/inference/inference';

describe('asynchronous transcription jobs', () => {
  it('returns immediately as pending and later exposes the transcript', async () => {
    let finish!: (value: string) => void;
    const transcription = {
      transcribe: vi.fn(() => new Promise<string>((resolve) => (finish = resolve))),
    } as unknown as TranscriptionService;
    const entries = { saveGuidedDraftAnswer: vi.fn() } as unknown as EntriesService;
    const formatting = {
      formatTranscript: vi.fn(async (_entryId: string, transcript: string) => transcript),
    } as TranscriptFormatting;
    const jobs = new TranscriptionJobsService(transcription, entries, formatting);

    const id = jobs.start(Buffer.from('audio'), {
      entryId: 'draft-1',
      questionKey: 'mind_body',
      orderIndex: 1,
    });
    expect(jobs.find(id)).toEqual({ status: 'pending' });

    finish('Kept transcript');
    await vi.waitFor(() =>
      expect(jobs.find(id)).toEqual({ status: 'completed', transcript: 'Kept transcript' }),
    );
    expect(entries.saveGuidedDraftAnswer).toHaveBeenCalledWith(
      'draft-1',
      'mind_body',
      'Kept transcript',
      1,
    );
    expect(entries.saveGuidedDraftAnswer).toHaveBeenCalledTimes(2);
  });
});
