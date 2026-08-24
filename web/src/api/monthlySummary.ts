import type { MonthlySummary } from '../domain/types';
import { api, type ApiResult } from './client';

/**
 * The month view's single source of truth.
 *
 * `totals_by_feeling` and `average_entries_per_day` arrive already computed and are rendered
 * verbatim — constitution Principle VII. Nothing downstream of this call may re-tally the days
 * array to produce its own counts or average: `days[].feelings` is the *distinct* set of feelings
 * seen on a day, so a client-side sum would legitimately disagree with the server's per-entry
 * totals, and SC-005 requires web and Android to show the same numbers 100% of the time.
 */
export function fetchMonthlySummary(month: string): Promise<ApiResult<MonthlySummary>> {
  return api.get<MonthlySummary>(`/monthly-summary?month=${encodeURIComponent(month)}`);
}
