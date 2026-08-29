import type { FeelingVocabulary } from '../domain/types';
import { api, type ApiResult } from './client';

/**
 * The feeling set comes from the backend, never from a constant in this repo — constitution
 * Principle VII. `valence` in particular is a rule (it drives each insight's keep/change
 * direction), and so is which group a feeling belongs to, so a hardcoded copy here could silently
 * disagree with the backend.
 *
 * Both shapes the endpoint serves are kept: `groups` is what the picker renders, `feelings` is
 * what a stored `feeling_key` is looked up in. Flattening one from the other here would be this
 * client deciding an ordering the backend already decided.
 */
export async function fetchFeelings(): Promise<ApiResult<FeelingVocabulary>> {
  const result = await api.get<FeelingVocabulary>('/feelings');
  if (!result.ok) return result;
  return {
    ok: true,
    value: {
      groups: result.value.groups ?? [],
      feelings: result.value.feelings ?? [],
    },
  };
}

/** Resolve stored keys to full feelings, dropping any this build has no entry for. */
export function resolveFeelings(vocabulary: FeelingVocabulary | null, keys: string[]) {
  if (!vocabulary) return [];
  const byKey = new Map(vocabulary.feelings.map((feeling) => [feeling.key, feeling]));
  return keys.flatMap((key) => {
    const feeling = byKey.get(key);
    return feeling ? [feeling] : [];
  });
}
