import type { GuidingQuestion } from '../domain/types';
import { api, type ApiResult } from './client';

/**
 * The question library comes from the backend, trigger keywords and all (Principle VII). Fetching
 * it once per session lets the composer decide which prompt to surface as the user types without a
 * network call mid-entry — which is what keeps the flow fast enough for SC-002.
 */
export async function fetchGuidingQuestions(): Promise<ApiResult<GuidingQuestion[]>> {
  const result = await api.get<{ questions: GuidingQuestion[] }>('/guiding-questions');
  return result.ok ? { ok: true, value: result.value.questions } : result;
}
