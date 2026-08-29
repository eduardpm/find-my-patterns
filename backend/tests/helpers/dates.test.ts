/**
 * Regression guard for #125 — pins the wall clock at an instant where the local calendar date and
 * the UTC calendar date genuinely disagree, so a future author who compares a UTC-written value
 * against `localDateString` (or vice versa) fails immediately, in CI, in UTC, on any date — rather
 * than only between local midnight and UTC midnight on whichever machine happens to run the suite
 * that night.
 *
 * The disagreement is reproduced through `todayLocal(simulatedUtcOffsetMinutes)`
 * (`src/db/codecs.ts`), not by reassigning `process.env.TZ`: this suite's Vitest pool runs every
 * file in one worker thread (`vitest.config.mts`, `pool: 'threads'`), and a worker thread's `Date`
 * reads the OS timezone once at thread start — confirmed by trying it first, here, and watching a
 * mid-test `process.env.TZ` write get silently ignored while a fresh top-level `node -e` process
 * observed the same write immediately. A test that trusted the reassignment would have looked like
 * it pinned CEST while actually asserting nothing about it. `vi.setSystemTime` has no such problem
 * — it replaces the global `Date` object outright rather than asking the OS for a timezone — so
 * only the *offset* needs simulating; the *instant* is pinned for real.
 */

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { encodeDate, encodeDateTime, nowUtc, todayLocal } from '../../src/db/codecs';
import { localDateString, utcDateString } from './dates';

// 23:30 UTC on New Year's Day. Shifted by a simulated UTC+2 (CEST, #125's own reproduction), local
// time is already 01:30 on the 2nd: local midnight has passed, UTC midnight has not.
const PINNED_UTC_INSTANT = '2026-01-01T23:30:00.000Z';
const SIMULATED_CEST_OFFSET_MINUTES = 120;

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date(PINNED_UTC_INSTANT));
});

afterEach(() => {
  vi.useRealTimers();
});

describe('the seam #125 lives on: nowUtc() vs a simulated todayLocal() inside the offending window', () => {
  it('genuinely disagree on the calendar date at this pinned instant', () => {
    expect(encodeDateTime(nowUtc()).slice(0, 10)).toBe('2026-01-01');
    expect(encodeDate(todayLocal(SIMULATED_CEST_OFFSET_MINUTES))).toBe('2026-01-02');
  });

  it('a value written by nowUtc() must never be checked against the other clock’s date', () => {
    // This is #125 itself, reproduced directly rather than described: the entries-write.test.ts
    // assertion this guards read `created_at`'s date (nowUtc) against `localDateString(0)`
    // (todayLocal) and passed every day except this one.
    const createdAtDate = encodeDateTime(nowUtc()).slice(0, 10);
    const entryDateUnderCest = encodeDate(todayLocal(SIMULATED_CEST_OFFSET_MINUTES));
    expect(createdAtDate).not.toBe(entryDateUnderCest);
  });
});

describe('localDateString / utcDateString mirror todayLocal() / nowUtc() under the real clock', () => {
  // No simulated offset here — this is a sanity check that the test helper's own arithmetic
  // (tests/helpers/dates.ts) agrees with codecs.ts's field-getter logic under whatever timezone
  // this process actually runs in, not a reproduction of the local/UTC divergence (which needs the
  // simulated offset above, for the reason in this file's header comment).
  it('localDateString(0) matches todayLocal()', () => {
    expect(localDateString(0)).toBe(encodeDate(todayLocal()));
  });

  it('utcDateString(0) matches nowUtc()’s date component', () => {
    expect(utcDateString(0)).toBe(encodeDateTime(nowUtc()).slice(0, 10));
  });
});
