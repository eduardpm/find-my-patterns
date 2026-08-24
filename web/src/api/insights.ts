import type { Insights } from '../domain/types';
import { api, type ApiResult } from './client';

/**
 * Detected patterns, exactly as the backend computed them.
 *
 * The response is returned whole rather than unwrapped, because `insufficient_data` is part of the
 * answer, not metadata about it: constitution Principle VII puts the minimum-occurrence threshold in
 * the backend, so the client is told there is not enough data — it never works that out from an
 * empty `patterns` list or from a count of its own (contracts/api.md `GET /insights`).
 */
export function fetchInsights(): Promise<ApiResult<Insights>> {
  return api.get<Insights>('/insights');
}
