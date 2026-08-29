import type { Insights, WhenInsights } from '../domain/types';
import { api, type ApiResult } from './client';

/**
 * Detected patterns, exactly as the backend computed them.
 *
 * The response is returned whole rather than unwrapped, because `insufficient_data` is part of the
 * answer, not metadata about it: constitution Principle VII puts the minimum-occurrence threshold in
 * the backend, so the client is told there is not enough data — it never works that out from an
 * empty `patterns` list or from a count of its own (contracts/api.md `GET /insights`).
 *
 * The same reasoning now covers `constants`: the window length, the minimum lift and the intensity
 * scale arrive with the answer so this client can say "in the last 30 days" without owning the 30.
 */
export function fetchInsights(): Promise<ApiResult<Insights>> {
  return api.get<Insights>('/insights');
}

/** The "when am I worst" view (I5). A separate question, and a separate request. */
export function fetchWhenInsights(): Promise<ApiResult<WhenInsights>> {
  return api.get<WhenInsights>('/insights/when');
}

/**
 * Mark the standing withdrawal notices as seen (A2-07).
 *
 * Explicit rather than a side effect of loading the screen: if merely opening Insights cleared the
 * flag, whichever device opened it first would clear it for the other, and the two would show
 * different numbers for the same diary.
 */
export function acknowledgeWithdrawals(): Promise<ApiResult<void>> {
  return api.post<void>('/insights/withdrawals/acknowledge', {});
}
