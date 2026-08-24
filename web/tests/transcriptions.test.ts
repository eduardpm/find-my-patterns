import { afterEach, describe, expect, it, vi } from 'vitest';
import { transcribeAudio } from '../src/api/transcriptions';

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

afterEach(() => {
  vi.restoreAllMocks();
  vi.useRealTimers();
});

describe('audio transcription polling', () => {
  it('uploads once, then polls the short-lived job for its result', async () => {
    vi.useFakeTimers();
    const fetch = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(jsonResponse(202, { id: 'job-1', status: 'pending' }))
      .mockResolvedValueOnce(
        jsonResponse(200, { status: 'completed', transcript: 'I went for a walk.' }),
      );

    const pending = transcribeAudio(
      new Blob(['audio'], { type: 'audio/webm' }),
      'draft-1',
      'mind_body',
      1,
    );
    await vi.advanceTimersByTimeAsync(1_000);

    await expect(pending).resolves.toEqual({ ok: true, value: 'I went for a walk.' });
    expect(fetch).toHaveBeenCalledTimes(2);
    expect(String(fetch.mock.calls[0]?.[0])).toBe(
      '/guided-entry-drafts/draft-1/questions/mind_body/transcriptions?order=1',
    );
    expect(String(fetch.mock.calls[1]?.[0])).toBe('/transcriptions/job-1');
  });
});
