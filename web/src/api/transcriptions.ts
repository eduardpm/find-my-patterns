import { api, type ApiResult } from './client';

interface StartedJob {
  id: string;
  status: 'pending';
}

type TranscriptionJob =
  | { status: 'pending' }
  | { status: 'completed'; transcript: string }
  | { status: 'failed'; error: string };

const POLL_INTERVAL_MS = 1_000;
const MAX_WAIT_MS = 10 * 60 * 1000;

const delay = (milliseconds: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, milliseconds));

export async function transcribeAudio(
  audio: Blob,
  draftKey: string,
  questionKey: string,
  orderIndex: number,
): Promise<ApiResult<string>> {
  const started = await api.postAudio<StartedJob>(
    `/guided-entry-drafts/${encodeURIComponent(draftKey)}/questions/${encodeURIComponent(questionKey)}/transcriptions?order=${orderIndex}`,
    audio,
  );
  if (!started.ok) return started;

  const deadline = Date.now() + MAX_WAIT_MS;
  while (Date.now() < deadline) {
    await delay(POLL_INTERVAL_MS);
    const result = await api.get<TranscriptionJob>(
      `/transcriptions/${encodeURIComponent(started.value.id)}`,
    );
    if (!result.ok) return result;
    if (result.value.status === 'completed') return { ok: true, value: result.value.transcript };
    if (result.value.status === 'failed') {
      return { ok: false, error: { kind: 'server', message: result.value.error } };
    }
  }

  return {
    ok: false,
    error: { kind: 'timeout', message: 'Transcription is taking longer than expected.' },
  };
}
