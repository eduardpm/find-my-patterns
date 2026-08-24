import type { Entry, EntryCreateInput, EntryUpdateInput } from '../domain/types';
import { api, type ApiResult } from './client';

export async function listEntries(date: string): Promise<ApiResult<Entry[]>> {
  const result = await api.get<{ entries: Entry[] }>(`/entries?date=${encodeURIComponent(date)}`);
  return result.ok ? { ok: true, value: result.value.entries } : result;
}

export function getEntry(id: string): Promise<ApiResult<Entry>> {
  return api.get<Entry>(`/entries/${encodeURIComponent(id)}`);
}

export function createEntry(input: EntryCreateInput): Promise<ApiResult<Entry>> {
  return api.post<Entry>('/entries', input);
}

/**
 * `version` is required: it is what the backend compares to decide whether this edit was based on
 * a current view (FR-011). A rejected call comes back as a `conflict` failure carrying the stored
 * entry, which the conflict screen renders beside the user's text (FR-023).
 */
export function updateEntry(id: string, input: EntryUpdateInput): Promise<ApiResult<Entry>> {
  return api.patch<Entry>(`/entries/${encodeURIComponent(id)}`, input);
}

/** FR-021: deletes carry the version too — a stale-view delete is the most destructive case. */
export function deleteEntry(id: string, version: number): Promise<ApiResult<void>> {
  return api.delete<void>(`/entries/${encodeURIComponent(id)}?version=${version}`);
}
