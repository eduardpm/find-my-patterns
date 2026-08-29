import { Inject, Injectable } from '@nestjs/common';
import { decodeDate, decodeDateTime } from '../db/codecs';
import { DIARY_DB } from '../db/database.provider';
import type { DiaryDatabase } from '../db/database';
import { averageValence, timeOfDayBucket, weekdayIndex, withinWindow } from './analysis';
import {
  CONFIRMED_FEELING_SOURCES,
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
    const byEntry = new Map<string, { weekday: number; timeOfDay: string; valences: string[] }>();
    for (const row of rows) {
      const entryDate = decodeDate(row.entry_date);
      if (!withinWindow(entryDate, today, RECENCY_WINDOW_DAYS)) continue;
      let entry = byEntry.get(row.id);
      if (!entry) {
        entry = {
          weekday: weekdayIndex(entryDate),
          timeOfDay: timeOfDayBucket(decodeDateTime(row.created_at)),
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
