import { Injectable } from '@nestjs/common';
import { encodeDate } from '../db/codecs';
import { EntriesRepository } from '../entries/entries.repository';

/**
 * Monthly aggregation (spec 002 FR-016).
 *
 * Three details are deliberate and each would be easy to "improve" into a divergence:
 *  - `totals_by_feeling` counts **entries**, while `days[].feelings` is the **distinct set** per
 *    day. Summing the day sets gives a different answer — which is the trap feature 003's web
 *    calendar test relies on.
 *  - the average divides by **days elapsed** (day-of-month for the current month, full month
 *    length otherwise), a value the client cannot compute for itself.
 *  - the average is **not rounded**. Both clients round for display; rounding here would change
 *    what they show.
 */

export interface DaySummary {
  date: string;
  feelings: string[];
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

  get(month: string): MonthlySummary {
    const { year, month: monthNum } = parseMonth(month);
    const monthLength = daysInMonth(year, monthNum);

    // The server's local calendar date, the same clock `entry_date` is assigned from.
    const today = new Date();
    const daysElapsed =
      year === today.getFullYear() && monthNum === today.getMonth() + 1
        ? today.getDate()
        : monthLength;

    const entries = this.entries.findInDateRange(
      { year, month: monthNum, day: 1 },
      { year, month: monthNum, day: monthLength },
    );

    const feelingsByDay = new Map<string, Set<string>>();
    const totals: Record<string, number> = {};
    let totalEntries = 0;

    for (const entry of entries) {
      totalEntries += 1;
      if (entry.feelingKey) {
        const key = encodeDate(entry.entryDate);
        if (!feelingsByDay.has(key)) feelingsByDay.set(key, new Set());
        feelingsByDay.get(key)!.add(entry.feelingKey);
        totals[entry.feelingKey] = (totals[entry.feelingKey] ?? 0) + 1;
      }
    }

    const days: DaySummary[] = [];
    for (let day = 1; day <= monthLength; day += 1) {
      const key = encodeDate({ year, month: monthNum, day });
      days.push({ date: key, feelings: [...(feelingsByDay.get(key) ?? [])].sort() });
    }

    return {
      month,
      days,
      totals_by_feeling: totals,
      average_entries_per_day: daysElapsed > 0 ? totalEntries / daysElapsed : 0.0,
    };
  }
}
