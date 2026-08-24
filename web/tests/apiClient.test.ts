/**
 * FR-013 / SC-007: when the backend is unreachable the user must be told, and no entry may ever be
 * reported as saved when it wasn't.
 *
 * The timeout cases are the point of this file. `fetch` has no default timeout, so without an
 * explicit abort a hung connection — the backend machine asleep, or a wrong IP — would spin
 * forever and SC-007's 10-second bound would have nothing behind it.
 */

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api, isConflict } from '../src/api/client';

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

describe('api client', () => {
  beforeEach(() => {
    vi.useRealTimers();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it('returns the parsed value on success', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(jsonResponse(200, { id: 'abc' }));

    const result = await api.get<{ id: string }>('/entries/abc');

    expect(result).toEqual({ ok: true, value: { id: 'abc' } });
  });

  it('reports a refused connection as unreachable rather than throwing', async () => {
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new TypeError('Failed to fetch'));

    const result = await api.get('/entries?date=2026-07-28');

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.kind).toBe('unreachable');
      expect(result.error.message).toMatch(/can't reach the diary server/i);
    }
  });

  it('reports a hung request as a timeout instead of hanging forever', async () => {
    // Never resolves until aborted — the "machine asleep" case.
    vi.spyOn(globalThis, 'fetch').mockImplementation(
      (_input, init) =>
        new Promise((_resolve, reject) => {
          init?.signal?.addEventListener('abort', () =>
            reject(new DOMException('Aborted', 'AbortError')),
          );
        }),
    );

    const result = await api.get('/entries?date=2026-07-28');

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.kind).toBe('timeout');
  }, 15000);

  it('aborts within SC-007 ten-second budget', async () => {
    let abortedAt = 0;
    const started = Date.now();
    vi.spyOn(globalThis, 'fetch').mockImplementation(
      (_input, init) =>
        new Promise((_resolve, reject) => {
          init?.signal?.addEventListener('abort', () => {
            abortedAt = Date.now() - started;
            reject(new DOMException('Aborted', 'AbortError'));
          });
        }),
    );

    await api.get('/entries?date=2026-07-28');

    expect(abortedAt).toBeGreaterThan(0);
    expect(abortedAt).toBeLessThan(10000);
  }, 15000);

  it('passes an abort signal on every request', async () => {
    const spy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(jsonResponse(200, {}));

    await api.get('/feelings');

    expect(spy.mock.calls[0]?.[1]?.signal).toBeInstanceOf(AbortSignal);
  });

  it('maps 404 to not_found', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      jsonResponse(404, { error: { code: 'not_found', message: 'Entry not found' } }),
    );

    const result = await api.get('/entries/gone');

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.kind).toBe('not_found');
  });

  it('maps an expired session to an actionable unauthorized failure', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      jsonResponse(401, { error: { code: 'unauthorized', message: 'Sign in.' } }),
    );

    const result = await api.get('/insights');

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.kind).toBe('unauthorized');
  });

  it('maps 409 to a conflict carrying the current entry (FR-023)', async () => {
    const current = { id: 'abc', raw_text: 'From the phone.', version: 2 };
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      jsonResponse(409, {
        error: { code: 'stale_entry', message: 'Changed elsewhere.' },
        current,
      }),
    );

    const result = await api.patch('/entries/abc', { raw_text: 'x', version: 1 });

    expect(isConflict(result)).toBe(true);
    if (isConflict(result)) {
      expect(result.error.current.version).toBe(2);
      expect(result.error.current.raw_text).toBe('From the phone.');
    }
  });

  it('treats a 204 as success with no body', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 204 }));

    const result = await api.delete('/entries/abc?version=1');

    expect(result.ok).toBe(true);
  });

  it('never reports a failed save as successful', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      jsonResponse(500, { error: { code: 'internal_error', message: 'boom' } }),
    );

    const result = await api.post('/entries', { mode: 'freeform', raw_text: 'x' });

    expect(result.ok).toBe(false);
  });
});
