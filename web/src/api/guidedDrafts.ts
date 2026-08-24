import type { Entry, GuidedAnswerInput } from '../domain/types';
import { api, type ApiResult } from './client';

export function createGuidedDraft(): Promise<ApiResult<{ draft_key: string }>> {
  return api.post('/guided-entry-drafts', {});
}

export function getGuidedDraft(
  draftKey: string,
): Promise<ApiResult<{ answers: GuidedAnswerInput[] }>> {
  return api.get(`/guided-entry-drafts/${encodeURIComponent(draftKey)}`);
}

export function saveGuidedDraftAnswer(
  draftKey: string,
  answer: GuidedAnswerInput,
  orderIndex: number,
): Promise<ApiResult<void>> {
  return api.put(
    `/guided-entry-drafts/${encodeURIComponent(draftKey)}/questions/${encodeURIComponent(answer.question_key)}`,
    { answer_text: answer.answer_text, order_index: orderIndex },
  );
}

export function finalizeGuidedDraft(draftKey: string): Promise<ApiResult<Entry>> {
  return api.post(`/guided-entry-drafts/${encodeURIComponent(draftKey)}/finalize`, {});
}

export function deleteGuidedDraft(draftKey: string): Promise<ApiResult<void>> {
  return api.delete(`/guided-entry-drafts/${encodeURIComponent(draftKey)}`);
}
