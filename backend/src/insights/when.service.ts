import { Inject, Injectable } from '@nestjs/common';
import { decodeDate, decodeDateTime } from '../db/codecs';
import { DIARY_DB } from '../db/database.provider';
import type { DiaryDatabase } from '../db/database';
import {
  averageValence,
  hourBlockKey,
  timeOfDayBucket,
  weekdayIndex,
  withinWindow,
} from './analysis';
import {
  CONFIRMED_FEELING_SOURCES,
  HOUR_BLOCKS,
  MIN_BUCKET_ENTRIES,
  RECENCY_WINDOW_DAYS,
  TIME_OF_DAY_BUCKETS,
  WEEKDAYS,
} from './constants';
import { todayLocal } from '../db/codecs';

/**
 * "When am I worst?" — answered from data the diary already holds (I5).
 *
 * No new capture burden and no new claim: these are time patterns, labelled as time patterns. A
 * bad Monday is a fact about Mondays in this diary, not a cause of anything (I5-06), and the
 * wording never says otherwise.
 *
 * Every bucket carries its own count. A bucket below `MIN_BUCKET_ENTRIES` is reported as
 * insufficient rather than as an average, because one entry is an anecdote and rendering it as
 * "-1.0" would give it the same visual weight as a month of them (I5-02, C-05).
 */

export interface WhenBucket {
  key: string;
  label: string;
  entry_count: number;
  /** Mean valence on the −1 … +1 scale, or `null` when there is not enough to average. */
  average_valence: number | null;
  /** Share of this bucket's entries carrying at least one negative feeling. */
  negative_rate: number | null;
  sufficient: boolean;
}

export interface WhenInsights {
  window_days: number;
  min_bucket_entries: number;
  total_entries: number;
  weekdays: WhenBucket[];
  times_of_day: WhenBucket[];
  best_weekday: string | null;
  worst_weekday: string | null;
  best_time_of_day: string | null;
  worst_time_of_day: string | null;
  /**
   * CH-5: mean valence and entry count per 2-hour block (`HOUR_BLOCKS`), for the heat strip under
   * "By time of day". Added alongside `times_of_day` rather than in place of it — the three-bucket
   * data is what every existing client (mobile, web, and their tests) already reads, and nothing
   * about that shape changes here.
   */
  hourly: WhenBucket[];
  best_hour: string | null;
  worst_hour: string | null;
  /**
   * The `times_of_day` bucket the diary writes into most, by entry count — not by valence, so this
   * is a separate field from `best_time_of_day`/`worst_time_of_day` rather than reusing `extreme`'s
   * tie-break. Null on a tie or on an empty window, same reasoning as `extreme` (I5-05): "entries
   * cluster in the evening" is a claim about counts the diary would have to actually support.
   */
  busiest_time_of_day: string | null;
}

interface Scored {
  bucket: string;
  valences: string[];
}

@Injectable()
export class WhenInsightsService {
  constructor(@Inject(DIARY_DB) private readonly db: DiaryDatabase) {}

  get(): WhenInsights {
    const placeholders = CONFIRMED_FEELING_SOURCES.map(() => '?').join(', ');
    // I5-07: unconfirmed feelings are not evidence here either. The filter is in the SQL so there
    // is no path through this service on which one could reach an average.
    const rows = this.db
      .prepare(
        `SELECT e.id, e.entry_date, e.created_at, f.valence
         FROM diary_entries e
         JOIN entry_feelings ef ON ef.entry_id = e.id
         JOIN feelings f ON f."key" = ef.feeling_key
         WHERE e.feeling_source IN (${placeholders})
         ORDER BY e.entry_date, e.id, ef.position`,
      )
      .all(...CONFIRMED_FEELING_SOURCES) as Array<{
      id: string;
      entry_date: string;
      created_at: string;
      valence: string;
    }>;

    const today = todayLocal();
    const byEntry = new Map<
      string,
      { weekday: number; timeOfDay: string; hourBlock: string; valences: string[] }
    >();
    for (const row of rows) {
      const entryDate = decodeDate(row.entry_date);
      if (!withinWindow(entryDate, today, RECENCY_WINDOW_DAYS)) continue;
      let entry = byEntry.get(row.id);
      if (!entry) {
        const createdAt = decodeDateTime(row.created_at);
        entry = {
          weekday: weekdayIndex(entryDate),
          timeOfDay: timeOfDayBucket(createdAt),
          hourBlock: hourBlockKey(createdAt),
          valences: [],
        };
        byEntry.set(row.id, entry);
      }
      entry.valences.push(row.valence);
    }

    const entries = [...byEntry.values()];
    const weekdays = WEEKDAYS.map((day, index) =>
      this.bucket(
        day.key,
        day.label,
        entries.filter((entry) => entry.weekday === index),
      ),
    );
    const timesOfDay = TIME_OF_DAY_BUCKETS.map((slot) =>
      this.bucket(
        slot.key,
        slot.label,
        entries.filter((entry) => entry.timeOfDay === slot.key),
      ),
    );
    const hourly = HOUR_BLOCKS.map((block) =>
      this.bucket(
        block.key,
        block.label,
        entries.filter((entry) => entry.hourBlock === block.key),
      ),
    );

    return {
      window_days: RECENCY_WINDOW_DAYS,
      min_bucket_entries: MIN_BUCKET_ENTRIES,
      total_entries: entries.length,
      weekdays,
      times_of_day: timesOfDay,
      best_weekday: extreme(weekdays, 'best'),
      worst_weekday: extreme(weekdays, 'worst'),
      best_time_of_day: extreme(timesOfDay, 'best'),
      worst_time_of_day: extreme(timesOfDay, 'worst'),
      hourly,
      best_hour: extreme(hourly, 'best'),
      worst_hour: extreme(hourly, 'worst'),
      busiest_time_of_day: busiest(timesOfDay),
    };
  }

  private bucket(
    key: string,
    label: string,
    entries: Scored[] | Array<{ valences: string[] }>,
  ): WhenBucket {
    const sufficient = entries.length >= MIN_BUCKET_ENTRIES;
    const negatives = entries.filter((entry) => entry.valences.includes('negative')).length;
    return {
      key,
      label,
      entry_count: entries.length,
      average_valence: sufficient ? averageValence(entries) : null,
      negative_rate: sufficient ? negatives / entries.length : null,
      sufficient,
    };
  }
}

/**
 * I5-05: the standout bucket, or nothing.
 *
 * Ties resolve to `null` rather than to whichever came first — calling a Monday the worst day when
 * Tuesday scored identically is a claim the data does not support, and the two clients would have
 * to agree on the tie-break for it to even be consistent.
 */
function extreme(buckets: WhenBucket[], want: 'best' | 'worst'): string | null {
  const usable = buckets.filter(
    (bucket): bucket is WhenBucket & { average_valence: number } => bucket.average_valence !== null,
  );
  if (usable.length < 2) return null;
  const sorted = [...usable].sort((a, b) =>
    want === 'best' ? b.average_valence - a.average_valence : a.average_valence - b.average_valence,
  );
  if (sorted[0].average_valence === sorted[1].average_valence) return null;
  return sorted[0].key;
}

/**
 * CH-5: the bucket with the most entries — by count, not by valence, which is the whole reason this
 * is not another call to `extreme`. Ties, and an all-empty list, resolve to `null` for the same
 * reason `extreme` does: a "diary clusters here" claim two equally-busy buckets do not support.
 */
function busiest(buckets: WhenBucket[]): string | null {
  if (buckets.length === 0) return null;
  const sorted = [...buckets].sort((a, b) => b.entry_count - a.entry_count);
  if (sorted[0].entry_count === 0) return null;
  if (sorted.length > 1 && sorted[0].entry_count === sorted[1].entry_count) return null;
  return sorted[0].key;
}
