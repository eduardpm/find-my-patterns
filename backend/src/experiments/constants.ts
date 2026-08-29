/**
 * Thresholds and defaults for N-of-1 experiments (R-3a, `specs/research/differentiator-opportunities.md` §D).
 *
 * Kept apart from the services that use them for the same reason `insights/constants.ts` is: a
 * number a client hardcodes is a number the two clients can disagree about. Every experiments
 * response carries `constants`, so a client can render "7–28 days" and explain "too few entries"
 * from the same numbers the backend used to decide them.
 */

import { MIN_BUCKET_ENTRIES } from '../insights/constants';

/** The default length offered when starting an experiment. */
export const DEFAULT_EXPERIMENT_LENGTH_DAYS = 7;

/** Below this, a window (weekday, time-of-day, or here) is too short to say anything about. */
export const MIN_EXPERIMENT_LENGTH_DAYS = 7;

/** A month is about as long as anyone can hold one variable steady and keep logging honestly. */
export const MAX_EXPERIMENT_LENGTH_DAYS = 28;

/**
 * The suppression floor for the results verdict.
 *
 * Deliberately the same constant `when.service.ts` uses for a weekday or time-of-day bucket
 * (I5-02) rather than a new number: the reasoning is identical — fewer than this many entries on
 * one side of the comparison and a single entry swings the rate by double digits, so the verdict
 * says so instead of reporting a precise-looking percentage.
 */
export const MIN_EXPERIMENT_BUCKET_ENTRIES = MIN_BUCKET_ENTRIES;

/** Everything above, in the shape every experiments response serves to clients. */
export interface ExperimentConstants {
  default_length_days: number;
  min_length_days: number;
  max_length_days: number;
  min_bucket_entries: number;
}

export function experimentConstants(): ExperimentConstants {
  return {
    default_length_days: DEFAULT_EXPERIMENT_LENGTH_DAYS,
    min_length_days: MIN_EXPERIMENT_LENGTH_DAYS,
    max_length_days: MAX_EXPERIMENT_LENGTH_DAYS,
    min_bucket_entries: MIN_EXPERIMENT_BUCKET_ENTRIES,
  };
}
