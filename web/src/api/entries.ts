import type { Entry, EntryCreateInput, EntryUpdateInput, PatternEcho } from '../domain/types';
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

/**
 * What the diary already says about the topics in an entry that has just been saved (I4).
 *
 * Called *after* a save and never before one. The echo is an observation about entries already
 * written; putting it in front of someone mid-sentence would shape the evidence it then counts.
 */
export async function fetchEntryEcho(id: string): Promise<ApiResult<PatternEcho[]>> {
  const result = await api.get<{ echoes: PatternEcho[] }>(
    `/entries/${encodeURIComponent(id)}/echo`,
  );
  return result.ok ? { ok: true, value: result.value.echoes } : result;
}
