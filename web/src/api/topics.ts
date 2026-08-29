import type { TopicDetail } from '../domain/types';
import { api, type ApiResult } from './client';

/**
 * The topic list and its aliases (A4-04).
 *
 * Aliases are the half of topic normalisation the backend cannot decide alone — "gym session" is
 * exercise in most diaries and something else in a physiotherapist's. Everything the user adds here
 * takes effect on the next recompute, with no model involved.
 */
export async function listTopics(): Promise<ApiResult<TopicDetail[]>> {
  const result = await api.get<{ topics: TopicDetail[] }>('/topics');
  return result.ok ? { ok: true, value: result.value.topics } : result;
}

export function addTopicAlias(topicId: string, alias: string): Promise<ApiResult<TopicDetail>> {
  return api.post<TopicDetail>(`/topics/${encodeURIComponent(topicId)}/aliases`, { alias });
}

export function removeTopicAlias(topicId: string, alias: string): Promise<ApiResult<TopicDetail>> {
  return api.delete<TopicDetail>(
    `/topics/${encodeURIComponent(topicId)}/aliases/${encodeURIComponent(alias)}`,
  );
}
