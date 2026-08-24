/**
 * The single place the web client talks to the backend.
 *
 * Two things here are requirements rather than plumbing:
 *
 *  - **The timeout.** `fetch` has no default one, so a hung connection (backend machine asleep,
 *    wrong IP) would spin forever and the user would never be told. SC-007 gives a 10-second bound;
 *    without an explicit abort there is no mechanism behind it.
 *  - **The 409 mapping.** A stale write comes back with the current entry attached, which is what
 *    lets the conflict screen show the user's text beside the stored version without a second round
 *    trip (FR-023, contracts/api.md).
 */

import type { Entry } from '../domain/types';

/** Below SC-007's 10s bound, leaving room to render the failure. */
const REQUEST_TIMEOUT_MS = 8000;

export type ApiFailureKind =
  'unreachable' | 'timeout' | 'unauthorized' | 'not_found' | 'conflict' | 'server';

export interface ApiFailure {
  kind: ApiFailureKind;
  message: string;
  /** Present only when `kind === 'conflict'`: the entry as actually stored (FR-023). */
  current?: Entry;
}

export type ApiResult<T> = { ok: true; value: T } | { ok: false; error: ApiFailure };

export function isConflict<T>(
  result: ApiResult<T>,
): result is { ok: false; error: ApiFailure & { current: Entry } } {
  return !result.ok && result.error.kind === 'conflict' && result.error.current !== undefined;
}

const UNREACHABLE_MESSAGE =
  "Can't reach the diary server. Check that it's running and that you're on the same network.";

interface ErrorEnvelope {
  error?: { code?: string; message?: string };
  current?: Entry;
}

function failureFromStatus(status: number, body: ErrorEnvelope | null): ApiFailure {
  const message = body?.error?.message;
  if (status === 409) {
    return {
      kind: 'conflict',
      message: message ?? 'This entry was changed somewhere else since you loaded it.',
      current: body?.current,
    };
  }
  if (status === 404) {
    return { kind: 'not_found', message: message ?? 'That entry no longer exists.' };
  }
  if (status === 401) {
    return { kind: 'unauthorized', message: 'Your session ended. Sign in again to continue.' };
  }
  return { kind: 'server', message: message ?? `The server returned an error (${status}).` };
}

async function request<T>(
  path: string,
  init?: RequestInit,
  timeoutMs = REQUEST_TIMEOUT_MS,
): Promise<ApiResult<T>> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(path, {
      ...init,
      signal: controller.signal,
      headers: {
        ...(init?.body ? { 'Content-Type': 'application/json' } : {}),
        ...init?.headers,
      },
    });

    if (response.status === 204) {
      return { ok: true, value: undefined as T };
    }

    let body: unknown = null;
    try {
      body = await response.json();
    } catch {
      body = null;
    }

    if (!response.ok) {
      return { ok: false, error: failureFromStatus(response.status, body as ErrorEnvelope | null) };
    }
    return { ok: true, value: body as T };
  } catch (err) {
    // An aborted request and a refused connection are the same story to the user: the entry did
    // not save (FR-013). Only the wording differs.
    if (err instanceof DOMException && err.name === 'AbortError') {
      return {
        ok: false,
        error: { kind: 'timeout', message: `${UNREACHABLE_MESSAGE} (timed out)` },
      };
    }
    return { ok: false, error: { kind: 'unreachable', message: UNREACHABLE_MESSAGE } };
  } finally {
    clearTimeout(timer);
  }
}

export const api = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, body: unknown) =>
    request<T>(path, { method: 'POST', body: JSON.stringify(body) }),
  patch: <T>(path: string, body: unknown) =>
    request<T>(path, { method: 'PATCH', body: JSON.stringify(body) }),
  put: <T>(path: string, body: unknown) =>
    request<T>(path, { method: 'PUT', body: JSON.stringify(body) }),
  delete: <T>(path: string) => request<T>(path, { method: 'DELETE' }),
  postAudio: <T>(path: string, audio: Blob) =>
    request<T>(
      path,
      {
        method: 'POST',
        body: audio,
        headers: { 'Content-Type': audio.type || 'audio/webm' },
      },
      30_000,
    ),
};
