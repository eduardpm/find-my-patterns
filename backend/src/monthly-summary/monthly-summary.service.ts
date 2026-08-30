import { Injectable } from '@nestjs/common';
import { encodeDate } from '../db/codecs';
import { EntriesRepository } from '../entries/entries.repository';

/**
 * Monthly aggregation (spec 002 FR-016).
 *
 * Four details are deliberate and each would be easy to "improve" into a divergence:
 *  - `totals_by_feeling` counts **entry–feeling pairs**, while `days[].feelings` is the
 *    **distinct set** per day. Summing the day sets gives a different answer — which is the trap
 *    feature 003's web calendar test relies on. Since an entry can carry several feelings, one
 *    entry now adds one to each of its feelings' totals; `average_entries_per_day` still counts
 *    entries, so the two no longer sum to the same number and were never meant to.
 *  - the average divides by **days elapsed** (day-of-month for the current month, full month
 *    length otherwise), a value the client cannot compute for itself.
 *  - the average is **not rounded**. Both clients round for display; rounding here would change
 *    what they show.
 *  - `days[].entry_count` (#72) is a *third* quantity, distinct from both of the above: the raw
 *    number of entries logged that day, counted once per entry regardless of how many feelings it
 *    carries or whether it carries any at all. It is **not** `feelings.length` — a day with ten
 *    entries all tagged `anxious` has `entry_count: 10` and `feelings: ['anxious']`. That gap is
 *    exactly why this field exists: #17's calendar volume bar originally read `feelings.length` as
 *    a stand-in for volume, which rendered such a day identically to a single-entry day.
 */

export interface DaySummary {
  date: string;
  feelings: string[];
  /**
   * The strongest intensity recorded on this day, or null when nothing was rated (I6-04).
   *
   * The maximum rather than the mean: the calendar cell answers "how much did this day register",
   * and averaging a rated 5 with two unrated entries would report a quieter day than the one the
   * user had. Optional throughout, so a user who never touches the dial sees exactly what they
   * saw before.
   */
  intensity: number | null;
  /**
   * The number of entries logged on this day (#72), counted once per entry — not the number of
   * feelings. See this file's doc comment for why `entry_count` and `feelings.length` are
   * different numbers and must stay that way.
   */
  entry_count: number;
}

export interface MonthlySummary {
  month: string;
  days: DaySummary[];
  totals_by_feeling: Record<string, number>;
  average_entries_per_day: number;
}

export class InvalidMonthError extends Error {}

function parseMonth(month: string): { year: number; month: number } {
  const parts = typeof month === 'string' ? month.split('-') : [];
  if (parts.length !== 2 || parts[0].length !== 4 || parts[1].length !== 2) {
    throw new InvalidMonthError(`Invalid month: '${month}', expected format YYYY-MM`);
  }
  const year = Number(parts[0]);
  const monthNum = Number(parts[1]);
  if (!Number.isInteger(year) || !Number.isInteger(monthNum)) {
    throw new InvalidMonthError(`Invalid month: '${month}', expected format YYYY-MM`);
  }
  if (monthNum < 1 || monthNum > 12) {
    throw new InvalidMonthError(`Invalid month: '${month}', expected format YYYY-MM`);
  }
  return { year, month: monthNum };
}

function daysInMonth(year: number, month: number): number {
  return new Date(year, month, 0).getDate();
}

@Injectable()
export class MonthlySummaryService {
  constructor(private readonly entries: EntriesRepository) {}

  get(userId: string, month: string): MonthlySummary {
    const { year, month: monthNum } = parseMonth(month);
    const monthLength = daysInMonth(year, monthNum);

    // The server's local calendar date, the same clock `entry_date` is assigned from.
    const today = new Date();
    const daysElapsed =
      year === today.getFullYear() && monthNum === today.getMonth() + 1
        ? today.getDate()
        : monthLength;

    const entries = this.entries.findInDateRange(
      userId,
      { year, month: monthNum, day: 1 },
      { year, month: monthNum, day: monthLength },
    );

    const feelingsByDay = new Map<string, Set<string>>();
    const intensityByDay = new Map<string, number>();
    const entryCountByDay = new Map<string, number>();
    const totals: Record<string, number> = {};
    let totalEntries = 0;

    for (const entry of entries) {
      totalEntries += 1;
      const key = encodeDate(entry.entryDate);
      // Incremented once per entry, outside the feelings loop below: an entry with no confirmed
      // feeling (feelingKeys is empty) must still count toward entry_count, even though it never
      // touches feelingsByDay or totals. That is the exact case the old feelings.length proxy got
      // wrong in the other direction — see this file's doc comment.
      entryCountByDay.set(key, (entryCountByDay.get(key) ?? 0) + 1);
      if (entry.feelingIntensity !== null) {
        intensityByDay.set(key, Math.max(intensityByDay.get(key) ?? 0, entry.feelingIntensity));
      }
      for (const feelingKey of entry.feelingKeys) {
        if (!feelingsByDay.has(key)) feelingsByDay.set(key, new Set());
        feelingsByDay.get(key)!.add(feelingKey);
        totals[feelingKey] = (totals[feelingKey] ?? 0) + 1;
      }
    }

    const days: DaySummary[] = [];
    for (let day = 1; day <= monthLength; day += 1) {
      const key = encodeDate({ year, month: monthNum, day });
      days.push({
        date: key,
        feelings: [...(feelingsByDay.get(key) ?? [])].sort(),
        intensity: intensityByDay.get(key) ?? null,
        entry_count: entryCountByDay.get(key) ?? 0,
      });
    }

    return {
      month,
      days,
      totals_by_feeling: totals,
      average_entries_per_day: daysElapsed > 0 ? totalEntries / daysElapsed : 0.0,
    };
  }
}
