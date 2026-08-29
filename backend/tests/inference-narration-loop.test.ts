/**
 * #88 — the narration loop guard.
 *
 * `llama-server` was pinned at 234% CPU for ~20 minutes with an empty job queue. The root cause:
 * `narrateNextPattern` reported a *rejected* suggestion the same as a written one (`return true`),
 * which let the worker's idle-only pacing (`if (!narrated) await delay(400)`) skip the delay
 * indefinitely — the same never-narratable pattern was retried against the model with no pacing
 * and no cap, forever.
 *
 * The first test below ("does not spin...") is the direct reproduction of that defect. Before this
 * fix existed, it was run — with `narrateNextPattern` swapped back to the unmodified `main`
 * version (boolean-returning, no attempt bookkeeping) — as thirty unconditional calls counting only
 * real suggestion requests (never the `keep_alive: 0` unload ping `worker.ts` also fires): thirty
 * calls in, thirty model calls out, no pacing, no cap, `suggestion_text` still the template. That
 * confirmed the bug was reproduced, not merely described, before any of the fix below was written.
 */

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { encodeDate, encodeDateTime, encodeJson, nowUtc, todayLocal } from '../src/db/codecs';
import { openDiary, type DiaryDatabase } from '../src/db/database';
import { initDiary } from '../src/db/init';
import {
  MAX_NARRATION_ATTEMPTS,
  NARRATION_BACKOFF_BASE_MS,
  NARRATION_BACKOFF_MAX_MS,
} from '../src/insights/constants';
import { narrateNextPattern, runWorker } from '../src/inference/worker';
import { templateSuggestionFor } from '../src/insights/patterns.service';

let dir: string;
let dbPath: string;
let db: DiaryDatabase;
let fetchSpy: ReturnType<typeof vi.spyOn>;
let suggestionCalls: string[];

const TEMPLATE = templateSuggestionFor('energised', 'walking');

function seedPattern(
  overrides: { narrationAttempts?: number; narrationNextAttemptAt?: string | null } = {},
): void {
  const now = encodeDateTime(nowUtc());
  db.prepare(
    `INSERT INTO topics (id, name, aliases, first_seen_at, last_seen_at)
     VALUES ('topic-1', 'walking', ?, ?, ?)`,
  ).run(encodeJson([]), now, now);
  db.prepare(
    `INSERT INTO diary_entries
     (id, created_at, updated_at, entry_date, mode, raw_text, feeling_key, feeling_source, version)
     VALUES ('entry-1', ?, ?, ?, 'freeform', 'A walk.', 'energised', 'confirmed', 1)`,
  ).run(now, now, encodeDate(todayLocal()));
  db.prepare(
    `INSERT INTO patterns
     (id, topic_id, feeling_key, occurrence_count, narrative_text, suggestion_text, direction,
      first_detected_at, last_updated_at, narration_attempts, narration_next_attempt_at)
     VALUES ('pattern-1', 'topic-1', 'energised', 5,
             'You felt energised in 5 recent entries mentioning walking.', ?, 'keep', ?, ?, ?, ?)`,
  ).run(
    TEMPLATE,
    now,
    now,
    overrides.narrationAttempts ?? 0,
    overrides.narrationNextAttemptAt ?? null,
  );
}

/** Stands in for Ollama's `/api/chat`, the same convention `inference-pairings.test.ts` uses:
 *  the real suggestion request always carries a non-empty `messages` array, the `keep_alive: 0`
 *  unload ping never does. */
function mockSuggestion(suggestion: string): void {
  suggestionCalls = [];
  fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation(async (_url, init) => {
    const body = init?.body ? (JSON.parse(String(init.body)) as { messages?: unknown[] }) : {};
    const isSuggestionCall = Array.isArray(body.messages) && body.messages.length > 0;
    if (isSuggestionCall) suggestionCalls.push(suggestion);
    return {
      ok: true,
      status: 200,
      json: async () =>
        isSuggestionCall
          ? { message: { content: JSON.stringify({ suggestion }) } }
          : { message: {} },
    } as Response;
  });
}

function readPattern(): {
  suggestion_text: string;
  narration_attempts: number;
  narration_next_attempt_at: string | null;
} {
  return db
    .prepare(
      'SELECT suggestion_text, narration_attempts, narration_next_attempt_at FROM patterns WHERE id = ?',
    )
    .get('pattern-1') as {
    suggestion_text: string;
    narration_attempts: number;
    narration_next_attempt_at: string | null;
  };
}

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diary-narration-'));
  dbPath = path.join(dir, 'diary.db');
  initDiary(dbPath);
  db = openDiary(dbPath);
  process.env.DATABASE_PATH = dbPath;
});

afterEach(() => {
  delete process.env.DATABASE_PATH;
  fetchSpy?.mockRestore();
  vi.useRealTimers();
  db.close();
  fs.rmSync(dir, { recursive: true, force: true });
});

describe('narrateNextPattern (#88)', () => {
  it('does not spin unpaced on a rejected pattern — at most one model call until its backoff elapses', async () => {
    seedPattern();
    // No topic stem, no digits: fails `acceptSuggestion` every time.
    mockSuggestion('Consider making a small change.');

    let lastOutcome: string = 'idle';
    for (let i = 0; i < 30; i += 1) {
      lastOutcome = await narrateNextPattern(db);
    }

    // The fix: the first attempt is made, rejected, and backs off. Every subsequent call in the
    // same instant sees `narration_next_attempt_at` still in the future and returns `idle` without
    // touching the model at all — this is the direct fix for #88's root cause.
    expect(suggestionCalls).toHaveLength(1);
    expect(lastOutcome).toBe('idle');

    const pattern = readPattern();
    expect(pattern.suggestion_text).toBe(TEMPLATE);
    expect(pattern.narration_attempts).toBe(1);
    expect(pattern.narration_next_attempt_at).not.toBeNull();
  });

  it('stops retrying after MAX_NARRATION_ATTEMPTS even once each backoff has elapsed', async () => {
    seedPattern();
    mockSuggestion('Consider making a small change.');
    vi.useFakeTimers();

    const outcomes: string[] = [];
    for (let i = 0; i < MAX_NARRATION_ATTEMPTS + 3; i += 1) {
      // Jump past the worst-case backoff so every iteration is eligible again, regardless of how
      // far the exponential schedule has grown — this isolates the cap from the backoff.
      vi.setSystemTime(new Date(Date.now() + NARRATION_BACKOFF_MAX_MS + 1000));
      outcomes.push(await narrateNextPattern(db));
    }

    // Exactly MAX_NARRATION_ATTEMPTS model calls, however many times the loop asked — this is the
    // "at most N model calls" acceptance criterion, satisfied by the cap rather than only by
    // pacing.
    expect(suggestionCalls).toHaveLength(MAX_NARRATION_ATTEMPTS);
    expect(outcomes.slice(0, MAX_NARRATION_ATTEMPTS).every((o) => o === 'attempted')).toBe(true);
    // And once the cap is hit, the worker is back to idle cadence: every further call is `idle`,
    // not merely delayed.
    expect(outcomes.slice(MAX_NARRATION_ATTEMPTS).every((o) => o === 'idle')).toBe(true);

    const pattern = readPattern();
    expect(pattern.narration_attempts).toBe(MAX_NARRATION_ATTEMPTS);
    expect(pattern.suggestion_text).toBe(TEMPLATE);

    // Confirm the cap really is permanent, not just a longer backoff: jump forward a full day and
    // try again.
    vi.setSystemTime(new Date(Date.now() + 24 * 60 * 60 * 1000));
    const finalOutcome = await narrateNextPattern(db);
    expect(finalOutcome).toBe('idle');
    expect(suggestionCalls).toHaveLength(MAX_NARRATION_ATTEMPTS);
  });

  it('backs off with growing spacing, not a fixed interval', async () => {
    seedPattern();
    mockSuggestion('Consider making a small change.');
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00.000Z'));

    await narrateNextPattern(db);
    const afterFirst = readPattern().narration_next_attempt_at;
    expect(afterFirst).not.toBeNull();

    // Not yet due: advancing by less than the base backoff must not trigger a second call.
    vi.setSystemTime(new Date(Date.now() + NARRATION_BACKOFF_BASE_MS - 1000));
    expect(await narrateNextPattern(db)).toBe('idle');
    expect(suggestionCalls).toHaveLength(1);

    // Due now: the base backoff has fully elapsed.
    vi.setSystemTime(new Date(Date.now() + 2000));
    expect(await narrateNextPattern(db)).toBe('attempted');
    expect(suggestionCalls).toHaveLength(2);
    const afterSecond = readPattern().narration_next_attempt_at;

    // The second backoff window is longer than the first (exponential, not fixed).
    expect(afterSecond! > afterFirst!).toBe(true);
  });

  it('writes an accepted suggestion and resets the attempt state', async () => {
    // Seed as if two prior rejections already happened, to prove acceptance clears them.
    seedPattern({ narrationAttempts: 2, narrationNextAttemptAt: null });
    mockSuggestion('Try a short walk after lunch and see whether the afternoon feels different.');

    const outcome = await narrateNextPattern(db);

    expect(outcome).toBe('wrote');
    expect(suggestionCalls).toHaveLength(1);
    const pattern = readPattern();
    expect(pattern.suggestion_text).toBe(
      'Try a short walk after lunch and see whether the afternoon feels different.',
    );
    expect(pattern.narration_attempts).toBe(0);
    expect(pattern.narration_next_attempt_at).toBeNull();
  });

  it('paces a model-call failure exactly like a rejection, never like progress', async () => {
    seedPattern();
    fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation(async (_url, init) => {
      const body = init?.body ? (JSON.parse(String(init.body)) as { messages?: unknown[] }) : {};
      const isSuggestionCall = Array.isArray(body.messages) && body.messages.length > 0;
      if (isSuggestionCall) throw new Error('ECONNREFUSED');
      return { ok: true, status: 200, json: async () => ({ message: {} }) } as Response;
    });

    const outcome = await narrateNextPattern(db);

    expect(outcome).toBe('attempted');
    const pattern = readPattern();
    expect(pattern.narration_attempts).toBe(1);
    expect(pattern.narration_next_attempt_at).not.toBeNull();
    expect(pattern.suggestion_text).toBe(TEMPLATE);
  });
});

describe('runWorker (#88 integration)', () => {
  it('makes at most one narration model call within a short run and never busy-spins', async () => {
    seedPattern();
    mockSuggestion('Consider making a small change.');

    const controller = new AbortController();
    const runPromise = runWorker(false, controller.signal);
    await new Promise((resolve) => setTimeout(resolve, 700));
    controller.abort();
    await runPromise;

    // `NARRATION_MIN_INTERVAL_MS` (5s) and the per-pattern backoff (60s base) both vastly exceed
    // this 700ms window, so the loop-level budget alone already caps this at one call — the
    // real-worker-loop counterpart to the direct `narrateNextPattern` tests above.
    expect(suggestionCalls.length).toBeLessThanOrEqual(1);
  }, 10_000);
});
