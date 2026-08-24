import type { Feeling } from '../domain/types';
import { api, type ApiResult } from './client';

/**
 * The feeling set comes from the backend, never from a constant in this repo — constitution
 * Principle VII. `valence` in particular is a rule (it drives each insight's keep/change
 * direction), so a hardcoded copy here could silently disagree with the backend.
 */
export async function fetchFeelings(): Promise<ApiResult<Feeling[]>> {
  const result = await api.get<{ feelings: Feeling[] }>('/feelings');
  return result.ok ? { ok: true, value: result.value.feelings } : result;
}
