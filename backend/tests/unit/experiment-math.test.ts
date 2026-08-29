/**
 * The arithmetic behind an experiment's results (R-3a) — pure, no database, no model.
 *
 * Mirrors `tests/unit/analysis.test.ts` in spirit: every number a client is shown has to be
 * reproducible from the diary's own entries, and the verdict sentences are asserted for their
 * exact text, not just their shape, because that sentence is the one honesty guarantee this
 * feature makes (never a causal claim, counts always shown, no invented percentage).
 */

import { describe, expect, it } from 'vitest';
import {
  addDays,
  baselineWindowFor,
  elapsedWindow,
  experimentVerdict,
  windowAssociation,
  windowLengthDays,
  type WindowAssociation,
} from '../../src/experiments/experiment-math';
import { MIN_EXPERIMENT_BUCKET_ENTRIES } from '../../src/experiments/constants';

const date = (year: number, month: number, day: number) => ({ year, month, day });

describe('calendar arithmetic', () => {
  it('shifts across a month boundary', () => {
    expect(addDays(date(2026, 8, 29), 3)).toEqual(date(2026, 9, 1));
    expect(addDays(date(2026, 9, 1), -3)).toEqual(date(2026, 8, 29));
  });

  it('shifts across a year boundary', () => {
    expect(addDays(date(2025, 12, 30), 3)).toEqual(date(2026, 1, 2));
  });

  it('counts a window inclusively — 7 days apart is an 8-day window, not 7', () => {
    expect(windowLengthDays(date(2026, 8, 1), date(2026, 8, 7))).toBe(7);
    expect(windowLengthDays(date(2026, 8, 1), date(2026, 8, 1))).toBe(1);
  });
});

describe('the elapsed window (how much of the plan has actually happened)', () => {
  it('is the full window once it has already ended', () => {
    const result = elapsedWindow(date(2026, 8, 1), date(2026, 8, 7), date(2026, 8, 20));
    expect(result).toEqual({ start: date(2026, 8, 1), end: date(2026, 8, 7) });
  });

  it('clamps the end to today while the experiment is still running', () => {
    const result = elapsedWindow(date(2026, 8, 1), date(2026, 8, 28), date(2026, 8, 10));
    expect(result).toEqual({ start: date(2026, 8, 1), end: date(2026, 8, 10) });
  });

  it('is the full window on the exact last day', () => {
    const result = elapsedWindow(date(2026, 8, 1), date(2026, 8, 7), date(2026, 8, 7));
    expect(result).toEqual({ start: date(2026, 8, 1), end: date(2026, 8, 7) });
  });

  it('never reports a negative-length window for an experiment that has not started yet', () => {
    const result = elapsedWindow(date(2026, 9, 1), date(2026, 9, 7), date(2026, 8, 20));
    expect(result).toEqual({ start: date(2026, 9, 1), end: date(2026, 9, 1) });
  });
});

describe('the baseline window (same length, immediately before start)', () => {
  it('ends the day before the experiment starts', () => {
    const result = baselineWindowFor(date(2026, 8, 15), 7);
    expect(result).toEqual({ start: date(2026, 8, 8), end: date(2026, 8, 14) });
    // Same length as what was asked for.
    expect(windowLengthDays(result.start, result.end)).toBe(7);
  });

  it('matches a partially-elapsed experiment window day for day', () => {
    // Only 3 days of the experiment have happened so far; the baseline mirrors exactly those 3.
    const result = baselineWindowFor(date(2026, 8, 15), 3);
    expect(result).toEqual({ start: date(2026, 8, 12), end: date(2026, 8, 14) });
  });

  it('crosses a month boundary the same way addDays does', () => {
    const result = baselineWindowFor(date(2026, 9, 3), 7);
    expect(result).toEqual({ start: date(2026, 8, 27), end: date(2026, 9, 2) });
  });
});

describe('windowAssociation (wraps analysis.ts, adds the day count)', () => {
  it('reuses associationFrom for the with-topic / without-topic split', () => {
    const assoc = windowAssociation(
      { presentCount: 3, presentTotal: 4, absentCount: 2, absentTotal: 5, daysWithTopic: 4 },
      date(2026, 8, 1),
      date(2026, 8, 7),
    );
    expect(assoc.presentCount).toBe(3);
    expect(assoc.presentTotal).toBe(4);
    expect(assoc.presentRate).toBeCloseTo(0.75, 5);
    expect(assoc.absentRate).toBeCloseTo(0.4, 5);
    expect(assoc.lift).toBeCloseTo(1.875, 5);
    expect(assoc.totalDays).toBe(7);
    expect(assoc.daysWithTopic).toBe(4);
  });

  it('carries the same comparison reason associationFrom would give — no invented lift', () => {
    // Only 2 entries without the topic: below MIN_COMPARISON_ENTRIES, so no lift is computed.
    const assoc = windowAssociation(
      { presentCount: 3, presentTotal: 4, absentCount: 1, absentTotal: 2, daysWithTopic: 4 },
      date(2026, 8, 1),
      date(2026, 8, 7),
    );
    expect(assoc.lift).toBeNull();
    expect(assoc.comparisonReason).toBe('insufficient_comparison');
  });
});

/** A ready-made window: 4 of 7 days mentioned the topic, 1 of those 4 entries carried the feeling. */
function windowOf(
  overrides: Partial<Parameters<typeof windowAssociation>[0]> = {},
): WindowAssociation {
  return windowAssociation(
    {
      presentCount: 1,
      presentTotal: 4,
      absentCount: 1,
      absentTotal: 2,
      daysWithTopic: 4,
      ...overrides,
    },
    date(2026, 8, 1),
    date(2026, 8, 7),
  );
}

describe('the verdict sentence (deterministic, never causal, counts always shown)', () => {
  it('states both windows’ counts and percentages — the sufficient-data case', () => {
    const experiment = windowOf({ presentCount: 1, presentTotal: 4, daysWithTopic: 4 });
    const baseline = windowOf({ presentCount: 3, presentTotal: 5, daysWithTopic: 5 });
    expect(baseline.presentTotal).toBeGreaterThanOrEqual(MIN_EXPERIMENT_BUCKET_ENTRIES);

    const { verdictText, insufficientData } = experimentVerdict(
      'exercise',
      'exhausted',
      experiment,
      baseline,
    );

    expect(verdictText).toBe(
      'During the experiment you mentioned exercise on 4 of 7 days; exhausted appeared in 1 of 4 ' +
        'entries (25%) vs 3 of 5 (60%) in the 7 days before.',
    );
    expect(insufficientData).toBe(false);
    // Never a causal claim — no "because", no "caused", no "protects".
    expect(verdictText).not.toMatch(/because|caused|protect/i);
  });

  it('appends the caveat, not a percentage it cannot back, when a window is too thin', () => {
    // Only 2 entries mentioned the topic during the experiment — below MIN_EXPERIMENT_BUCKET_ENTRIES.
    const experiment = windowOf({ presentCount: 1, presentTotal: 2, daysWithTopic: 2 });
    const baseline = windowOf({ presentCount: 3, presentTotal: 5, daysWithTopic: 5 });

    const { verdictText, insufficientData } = experimentVerdict(
      'exercise',
      'exhausted',
      experiment,
      baseline,
    );

    expect(insufficientData).toBe(true);
    expect(verdictText).toBe(
      'During the experiment you mentioned exercise on 2 of 7 days; exhausted appeared in 1 of 2 ' +
        'entries (50%) vs 3 of 5 (60%) in the 7 days before. Too few entries to be sure.',
    );
    // The count and percentage are still shown — insufficient data caveats, it does not hide.
    expect(verdictText).toContain('1 of 2');
  });

  it('does not fabricate a rate when the topic was never mentioned during the experiment', () => {
    const experiment = windowOf({ presentCount: 0, presentTotal: 0, daysWithTopic: 0 });
    const baseline = windowOf({ presentCount: 3, presentTotal: 5, daysWithTopic: 5 });

    const { verdictText, insufficientData } = experimentVerdict(
      'exercise',
      'exhausted',
      experiment,
      baseline,
    );

    expect(verdictText).toBe('You have not mentioned exercise yet during the experiment.');
    expect(insufficientData).toBe(true);
    expect(verdictText).not.toMatch(/%/);
  });

  it('does not fabricate a rate when the topic was never mentioned before the experiment either', () => {
    const experiment = windowOf({ presentCount: 1, presentTotal: 4, daysWithTopic: 4 });
    const baseline = windowOf({ presentCount: 0, presentTotal: 0, daysWithTopic: 0 });

    const { verdictText, insufficientData } = experimentVerdict(
      'exercise',
      'exhausted',
      experiment,
      baseline,
    );

    expect(verdictText).toBe(
      'You did not mention exercise in the 7 days before the experiment, so there is nothing to ' +
        'compare it to.',
    );
    expect(insufficientData).toBe(true);
  });

  it('uses singular "day" and "entry" for a count of exactly one', () => {
    const experiment = windowAssociation(
      { presentCount: 1, presentTotal: 1, absentCount: 0, absentTotal: 1, daysWithTopic: 1 },
      date(2026, 8, 7),
      date(2026, 8, 7),
    );
    const baseline = windowAssociation(
      { presentCount: 1, presentTotal: 1, absentCount: 0, absentTotal: 1, daysWithTopic: 1 },
      date(2026, 8, 6),
      date(2026, 8, 6),
    );

    const { verdictText } = experimentVerdict('exercise', 'exhausted', experiment, baseline);

    expect(verdictText).toBe(
      'During the experiment you mentioned exercise on 1 of 1 day; exhausted appeared in 1 of 1 ' +
        'entry (100%) vs 1 of 1 (100%) in the 1 day before. Too few entries to be sure.',
    );
  });
});
