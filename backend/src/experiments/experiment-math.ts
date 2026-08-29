/**
 * The arithmetic behind an experiment's results — pure, database-free, LLM-free.
 *
 * Mirrors `insights/analysis.ts` on purpose: an experiment's "during" window and "before" window
 * are each counted exactly the way a pattern's "with the topic" and "without the topic" groups
 * are — through `associationFrom`, imported and reused rather than re-derived. What is new here is
 * only what an experiment adds on top: a second window instead of a second group, a day-count
 * instead of a percentage, and a verdict sentence with its own honesty rule.
 *
 * That rule, stated once: **a rate is never shown as more certain than the count behind it.**
 * Every count is always shown, in both windows — but when either window's "mentioned the topic"
 * total falls below `MIN_EXPERIMENT_BUCKET_ENTRIES`, the sentence adds a plain caveat rather than
 * silently keeping quiet or rounding a two-entry sample into a confident-looking percentage. And
 * the sentence never claims causation — "appeared in", "vs", never "because" or "caused by"
 * (mirrors A3-08 / I1-07 in `analysis.ts`).
 */

import type { PlainDate } from '../db/codecs';
import { associationFrom, daysBetween, percent, type Association } from '../insights/analysis';
import { MIN_EXPERIMENT_BUCKET_ENTRIES } from './constants';

/** `date` shifted by `delta` calendar days (negative moves earlier). */
export function addDays(date: PlainDate, delta: number): PlainDate {
  const utc = Date.UTC(date.year, date.month - 1, date.day) + delta * 86_400_000;
  const shifted = new Date(utc);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}

/** Inclusive day count between two calendar dates — a 7-day window's `start` and `end` differ by 6. */
export function windowLengthDays(start: PlainDate, end: PlainDate): number {
  return daysBetween(start, end) + 1;
}

/**
 * How much of the planned experiment window has actually happened.
 *
 * An experiment is created for a future span (`start_date` to `end_date`), but results can only
 * ever be read off days that have already been logged. This clamps the window's end to today —
 * never later, and never earlier than `start` for an experiment whose start is still ahead — so a
 * results call mid-experiment reports "so far" honestly instead of reading past entries that don't
 * exist yet.
 */
export function elapsedWindow(
  start: PlainDate,
  end: PlainDate,
  today: PlainDate,
): { start: PlainDate; end: PlainDate } {
  // `daysBetween(today, end)` is `end - today`: positive while `end` is still ahead of today, so
  // that side clamps to today; zero or negative once `end` has arrived or passed, so that side is
  // used as-is — the window is already over and every day of it is real.
  const cappedEnd = daysBetween(today, end) > 0 ? today : end;
  // And never before `start`: an experiment whose start is still ahead has zero elapsed days, not
  // a negative-length window.
  const effectiveEnd = daysBetween(start, cappedEnd) < 0 ? start : cappedEnd;
  return { start, end: effectiveEnd };
}

/**
 * The baseline window: the same number of days as the elapsed experiment window, immediately
 * before it starts. Same length is the entire point — a 4-day "so far" is only a fair comparison
 * against another 4 days, not against the two weeks the experiment was planned to run.
 */
export function baselineWindowFor(
  experimentStart: PlainDate,
  elapsedDays: number,
): { start: PlainDate; end: PlainDate } {
  const end = addDays(experimentStart, -1);
  const start = addDays(end, -(elapsedDays - 1));
  return { start, end };
}

/** The raw counts a window's association is built from — see `WindowAssociation`. */
export interface WindowCounts {
  /** Entries mentioning the topic, with the feeling. */
  presentCount: number;
  /** Entries mentioning the topic. */
  presentTotal: number;
  /** Entries not mentioning the topic, with the feeling. */
  absentCount: number;
  /** Entries not mentioning the topic. */
  absentTotal: number;
  /** Distinct calendar days on which the topic was mentioned at least once. */
  daysWithTopic: number;
}

export interface WindowAssociation extends Association {
  start: PlainDate;
  end: PlainDate;
  totalDays: number;
  daysWithTopic: number;
}

/** Builds one window's association from its raw counts — the "with topic / without topic" split. */
export function windowAssociation(
  counts: WindowCounts,
  start: PlainDate,
  end: PlainDate,
): WindowAssociation {
  return {
    ...associationFrom(
      counts.presentCount,
      counts.presentTotal,
      counts.absentCount,
      counts.absentTotal,
    ),
    start,
    end,
    totalDays: windowLengthDays(start, end),
    daysWithTopic: counts.daysWithTopic,
  };
}

const pluralWord = (count: number, one: string, many: string): string => (count === 1 ? one : many);

/**
 * The deterministic verdict, stated with the numbers that produced it.
 *
 * Compares the **"mentioned the topic" rate** across the two windows — experiment vs before — not
 * the "with topic / without topic" split within either one. That is the honest question an
 * experiment answers: did the feeling turn up less often alongside the topic during the test than
 * it did in the same length of time before it. The with/without split each window also carries
 * (`WindowAssociation.absentCount` etc.) is the supporting evidence a client can drill into; it is
 * not what this sentence states.
 */
export function experimentVerdict(
  topic: string,
  feelingLabel: string,
  experiment: WindowAssociation,
  baseline: WindowAssociation,
): { verdictText: string; insufficientData: boolean } {
  if (experiment.presentTotal === 0) {
    return {
      verdictText: `You have not mentioned ${topic} yet during the experiment.`,
      insufficientData: true,
    };
  }
  if (baseline.presentTotal === 0) {
    return {
      verdictText:
        `You did not mention ${topic} in the ${baseline.totalDays} ` +
        `${pluralWord(baseline.totalDays, 'day', 'days')} before the experiment, so there is ` +
        `nothing to compare it to.`,
      insufficientData: true,
    };
  }

  const insufficientData =
    experiment.presentTotal < MIN_EXPERIMENT_BUCKET_ENTRIES ||
    baseline.presentTotal < MIN_EXPERIMENT_BUCKET_ENTRIES;

  const sentence =
    `During the experiment you mentioned ${topic} on ${experiment.daysWithTopic} of ` +
    `${experiment.totalDays} ${pluralWord(experiment.totalDays, 'day', 'days')}; ${feelingLabel} ` +
    `appeared in ${experiment.presentCount} of ${experiment.presentTotal} ` +
    `${pluralWord(experiment.presentTotal, 'entry', 'entries')} ` +
    `(${percent(experiment.presentRate ?? 0)}%) vs ${baseline.presentCount} of ` +
    `${baseline.presentTotal} (${percent(baseline.presentRate ?? 0)}%) in the ${baseline.totalDays} ` +
    `${pluralWord(baseline.totalDays, 'day', 'days')} before.`;

  return {
    verdictText: insufficientData ? `${sentence} Too few entries to be sure.` : sentence,
    insufficientData,
  };
}
