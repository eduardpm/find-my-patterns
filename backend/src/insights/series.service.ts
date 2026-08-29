import { Injectable } from '@nestjs/common';
import { decodeDate, encodeDate } from '../db/codecs';
import type { PlainDate } from '../db/codecs';
import { EntriesRepository, FeelingsRepository } from '../entries/entries.repository';
import { daysBetween, monthStart, weekStart } from './analysis';
import {
  CONFIRMED_FEELING_SOURCES,
  MAX_SERIES_RANGE_DAYS,
  VALENCE_SCORE,
  engineConstants,
  type EngineConstants,
} from './constants';

/**
 * CH-0: the shared prerequisite behind every planned chart — see the day-score doc comment above
 * `MAX_SERIES_RANGE_DAYS` in `constants.ts` for the definition this file implements.
 *
 * One SQL pass over the range (`EntriesRepository.findInDateRange`, already batched — see its own
 * docs on why a per-entry feelings lookup would be an N+1 query), plus one read of the feeling
 * vocabulary for the valence each feeling key carries. Neither cost scales with the number of days
 * requested; both scale with the number of entries in the range, which is the data this endpoint is
 * summarising anyway.
 */

export type SeriesGranularity = 'day' | 'week' | 'month';

export interface SeriesPoint {
  /** The day, or the period's start date, as `YYYY-MM-DD`. */
  date: string;
  /** Mean `VALENCE_SCORE` of confirmed feelings, or `null` — see the day-score doc in `constants.ts`. */
  score: number | null;
  entry_count: number;
  confirmed_feeling_count: number;
}

export interface SeriesOut {
  granularity: SeriesGranularity;
  points: SeriesPoint[];
  /** The same shape `GET /insights` serves as `constants` (Principle VII) — not a second contract. */
  constants: EngineConstants;
}

/** A malformed or out-of-range request. The controller maps this to the API's validation status. */
export class InvalidSeriesRangeError extends Error {}

interface DayBucket {
  entryCount: number;
  /** One `VALENCE_SCORE` value per confirmed feeling recorded that day, flattened (see constants.ts). */
  confirmedScores: number[];
}

@Injectable()
export class SeriesService {
  constructor(
    private readonly entries: EntriesRepository,
    private readonly feelings: FeelingsRepository,
  ) {}

  /**
   * `maxRangeDays` (M-3, #48): the free/paid boundary for this endpoint, entitlement-derived at the
   * controller (`InsightsController#windowDaysFor`) and passed in here rather than looked up —
   * this service has no notion of "who is asking", the same separation `PatternsService` keeps
   * between deciding a window and deciding a tier. `null` (premium) applies no additional ceiling
   * beyond the existing day-granularity `MAX_SERIES_RANGE_DAYS` check below; a number (free) rejects
   * *any* granularity's request once the requested span exceeds it — deliberately not only
   * `granularity === 'day'` the way the day-only check is, because a free-tier `granularity=month`
   * request spanning years would otherwise aggregate a full-history series into a handful of
   * points and hand it over anyway, defeating the cap in spirit while honouring it in letter.
   */
  getSeries(
    fromRaw: string,
    toRaw: string,
    granularity: SeriesGranularity = 'day',
    maxRangeDays: number | null = null,
  ): SeriesOut {
    const from = parseSeriesDate(fromRaw, 'from');
    const to = parseSeriesDate(toRaw, 'to');
    const spanDays = daysBetween(from, to) + 1;

    if (spanDays <= 0) {
      throw new InvalidSeriesRangeError(`'from' (${fromRaw}) must not be after 'to' (${toRaw})`);
    }
    if (maxRangeDays !== null && spanDays > maxRangeDays) {
      throw new InvalidSeriesRangeError(
        `Free tier is limited to a ${maxRangeDays}-day range: ${spanDays} days requested`,
      );
    }
    // Only day granularity is capped (CH-0): a week/month request over the same span already
    // returns far fewer points, so the response it produces never grows the way a daily one would.
    if (granularity === 'day' && spanDays > MAX_SERIES_RANGE_DAYS) {
      throw new InvalidSeriesRangeError(
        `Range too large for granularity=day: ${spanDays} days requested, ${MAX_SERIES_RANGE_DAYS} is the max`,
      );
    }

    const days = this.dayPoints(from, to);
    const points = granularity === 'day' ? days : aggregate(days, granularity);
    // Same reasoning as `InsightsController#get`'s `constants` block: report the window this
    // response was actually bound by, not always the engine's default — a premium reader who hit
    // no cap at all must not be told "30 days" just because that is what free would have used.
    return { granularity, points, constants: engineConstants(maxRangeDays) };
  }

  /** Every day with at least one entry in `[from, to]`, in one pass over one query's rows. */
  private dayPoints(from: PlainDate, to: PlainDate): SeriesPoint[] {
    const entries = this.entries.findInDateRange(from, to);
    const valenceOf = new Map(
      this.feelings.findAll().map((feeling) => [feeling.key, VALENCE_SCORE[feeling.valence]]),
    );

    const byDay = new Map<string, DayBucket>();
    for (const entry of entries) {
      const key = encodeDate(entry.entryDate);
      let bucket = byDay.get(key);
      if (!bucket) {
        bucket = { entryCount: 0, confirmedScores: [] };
        byDay.set(key, bucket);
      }
      bucket.entryCount += 1;
      // I5-07's rule again: a suggestion nobody confirmed is not evidence, so it moves the entry
      // count but never the score.
      if (CONFIRMED_FEELING_SOURCES.includes(entry.feelingSource)) {
        for (const feelingKey of entry.feelingKeys) {
          const score = valenceOf.get(feelingKey);
          if (score !== undefined) bucket.confirmedScores.push(score);
        }
      }
    }

    return [...byDay.entries()]
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([date, bucket]) => ({
        date,
        score: bucket.confirmedScores.length > 0 ? mean(bucket.confirmedScores) : null,
        entry_count: bucket.entryCount,
        confirmed_feeling_count: bucket.confirmedScores.length,
      }));
  }
}

/**
 * Week and month points from day points — a mean of day scores, never a re-pooling of feelings
 * (see the day-score doc comment in `constants.ts` for why). `entry_count` and
 * `confirmed_feeling_count` are sums across the period's days: those are still real counts of real
 * rows, unlike the score, which is deliberately an average of averages.
 */
function aggregate(days: SeriesPoint[], granularity: 'week' | 'month'): SeriesPoint[] {
  const periodStart = granularity === 'week' ? weekStart : monthStart;

  interface PeriodBucket {
    entryCount: number;
    confirmedFeelingCount: number;
    dayScores: number[];
  }
  const byPeriod = new Map<string, PeriodBucket>();

  for (const point of days) {
    const key = encodeDate(periodStart(decodeDate(point.date)));
    let bucket = byPeriod.get(key);
    if (!bucket) {
      bucket = { entryCount: 0, confirmedFeelingCount: 0, dayScores: [] };
      byPeriod.set(key, bucket);
    }
    bucket.entryCount += point.entry_count;
    bucket.confirmedFeelingCount += point.confirmed_feeling_count;
    if (point.score !== null) bucket.dayScores.push(point.score);
  }

  return [...byPeriod.entries()]
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([date, bucket]) => ({
      date,
      score: bucket.dayScores.length > 0 ? mean(bucket.dayScores) : null,
      entry_count: bucket.entryCount,
      confirmed_feeling_count: bucket.confirmedFeelingCount,
    }));
}

function mean(values: number[]): number {
  return values.reduce((total, value) => total + value, 0) / values.length;
}

function parseSeriesDate(value: string, field: 'from' | 'to'): PlainDate {
  try {
    return decodeDate(value);
  } catch {
    throw new InvalidSeriesRangeError(
      `Invalid '${field}' date: '${value}', expected format YYYY-MM-DD`,
    );
  }
}
