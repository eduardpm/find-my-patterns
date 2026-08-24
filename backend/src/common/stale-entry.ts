import type { DiaryEntry } from '../domain/types';

export const STALE_MESSAGE = 'This entry was changed somewhere else since you loaded it.';

/**
 * Raised when a mutation is based on a version that is no longer current (FR-011).
 *
 * Carries the entry **as actually stored** so the API layer can return it inside the 409 body —
 * which is what lets both clients show the user's text beside the stored version without a second
 * round trip (FR-023).
 */
export class StaleEntryError extends Error {
  constructor(readonly current: DiaryEntry) {
    super(`Entry ${current.id} has changed since it was read`);
  }
}

/**
 * The 409 body: `{"error": {...}, "current": {...}}`.
 *
 * Built here and returned **directly** by the controller rather than thrown, because the global
 * error filter rebuilds every exception as `{"error": ...}` alone — which would silently drop
 * `current` and relabel the code as `error` (contracts/api.md).
 */
export function staleEntryBody(currentOut: Record<string, unknown>): Record<string, unknown> {
  return {
    error: { code: 'stale_entry', message: STALE_MESSAGE },
    current: currentOut,
  };
}
