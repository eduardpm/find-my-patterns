import type { CSSProperties } from 'react';
import type { FeelingVocabulary, MonthlyDay } from '../domain/types';

interface Props {
  /** The month being shown, `YYYY-MM`. Used only for the caption and cell labels. */
  month: string;
  /** One item per day of the month, exactly as the backend returned them. */
  days: MonthlyDay[];
  /** Resolves the keys in `days[].feelings` to their labels and groups. */
  vocabulary: FeelingVocabulary | null;
}

/**
 * Key → label and group, for the summary shapes that carry bare feeling keys.
 *
 * The month summary sends keys, not feelings, because a key is what the aggregation is over. Both
 * the label and the group colour still belong to the vocabulary, so they are looked up rather than
 * derived — and a key this build has no entry for still renders, just plainly.
 */
export interface FeelingLookup {
  label: (key: string) => string;
  groupKey: (key: string) => string | undefined;
}

export function feelingLookup(vocabulary: FeelingVocabulary | null): FeelingLookup {
  const byKey = new Map((vocabulary?.feelings ?? []).map((feeling) => [feeling.key, feeling]));
  return {
    label: (key) => byKey.get(key)?.label ?? feelingLabel(key),
    groupKey: (key) => byKey.get(key)?.group_key,
  };
}

/** Monday-first, matching the Android calendar so the two clients read the same (SC-005). */
const WEEKDAYS = [
  { short: 'Mon', long: 'Monday' },
  { short: 'Tue', long: 'Tuesday' },
  { short: 'Wed', long: 'Wednesday' },
  { short: 'Thu', long: 'Thursday' },
  { short: 'Fri', long: 'Friday' },
  { short: 'Sat', long: 'Saturday' },
  { short: 'Sun', long: 'Sunday' },
];

/**
 * Last-resort label for a key the vocabulary has no entry for — a feeling the backend gained after
 * this build shipped. `feelingLookup` prefers the backend's own label, which is the authority
 * (Principle VII); this exists so an unknown key is still readable rather than absent.
 */
export function feelingLabel(key: string): string {
  const words = key.split('_').filter(Boolean);
  if (words.length === 0) return key;
  return words.map((w) => w[0].toUpperCase() + w.slice(1)).join(' ');
}

/**
 * The accent for a feeling's *group*, from tokens.css, falling back to the neutral outline for a
 * group this client has no colour for. Colour is decoration here — every dot is also named in text,
 * because FR-027 forbids conveying meaning by colour alone.
 *
 * Keyed on the group rather than the feeling because the vocabulary is around thirty words and a
 * calendar dot is 8px across: four accents a reader can actually tell apart beat thirty they
 * cannot. See the token block in `tokens.css`.
 */
export function feelingDotStyle(groupKey: string | undefined): CSSProperties {
  return {
    backgroundColor: groupKey
      ? `var(--feeling-group-${groupKey}, var(--color-outline))`
      : 'var(--color-outline)',
  };
}

/** `2026-07-04` → `4`, without constructing a Date and inviting a timezone shift. */
function dayOfMonth(isoDate: string): number {
  return Number(isoDate.slice(8, 10));
}

/**
 * Today, as a local `YYYY-MM-DD`.
 *
 * Local rather than UTC because "today" on a calendar is a local-calendar question — the same
 * reason `MonthlyCalendarScreen.currentMonth` works this way. Compared as strings so the day cells,
 * which arrive as ISO dates, never have to become Date objects and pick up a timezone shift.
 */
function todayIso(): string {
  const now = new Date();
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}

/** 0 = Monday … 6 = Sunday. Parsed as UTC so the local timezone can't move the date. */
function mondayFirstWeekday(isoDate: string): number {
  const parsed = new Date(`${isoDate}T00:00:00Z`);
  return (parsed.getUTCDay() + 6) % 7;
}

/** `2026-07` → `July 2026`, in the reader's locale. Presentation, not a rule. */
export function monthLabel(month: string): string {
  const parsed = new Date(`${month}-01T00:00:00Z`);
  if (Number.isNaN(parsed.getTime())) return month;
  return new Intl.DateTimeFormat(undefined, {
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(parsed);
}

/**
 * The month grid (US5 AC1/AC3/AC4).
 *
 * Two acceptance criteria drive the cell design:
 *
 *  - **AC3** — a day can hold more than one feeling, so every feeling gets its own dot rather than
 *    the day collapsing to a single "dominant" one. Picking a winner would also be a rule, which
 *    Principle VII puts in the backend, not here.
 *  - **AC4** — days with nothing logged must be distinguishable. They are, three ways over: a
 *    dashed rather than solid border, a dimmed number, and the words "no entries" in the cell's
 *    hidden label. Never by colour alone (FR-027).
 *
 * It is a real `<table>`: a month grid genuinely is tabular data, and a table gives screen readers
 * the row/column relationships for free, which a div grid would have to reconstruct with ARIA.
 */
export function CalendarGrid({ month, days, vocabulary }: Props) {
  const label = monthLabel(month);
  const today = todayIso();
  const lookup = feelingLookup(vocabulary);

  if (days.length === 0) {
    return <p className="muted">No days to show for {label}.</p>;
  }

  const leadingBlanks = mondayFirstWeekday(days[0].date);
  const cells: (MonthlyDay | null)[] = [...Array<null>(leadingBlanks).fill(null), ...days];
  while (cells.length % 7 !== 0) cells.push(null);

  const weeks: (MonthlyDay | null)[][] = [];
  for (let i = 0; i < cells.length; i += 7) {
    weeks.push(cells.slice(i, i + 7));
  }

  return (
    <table className="calendar">
      <caption className="visually-hidden">
        Feelings logged each day of {label}. Days with no entries are marked as such.
      </caption>
      <thead>
        <tr>
          {WEEKDAYS.map((day) => (
            <th key={day.short} scope="col">
              <abbr title={day.long}>{day.short}</abbr>
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {weeks.map((week, weekIndex) => (
          <tr key={weekIndex}>
            {week.map((day, dayIndex) =>
              day ? (
                <DayCell
                  key={day.date}
                  day={day}
                  month={label}
                  isToday={day.date === today}
                  lookup={lookup}
                />
              ) : (
                <td key={`blank-${weekIndex}-${dayIndex}`} className="calendar-day--outside" />
              ),
            )}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function DayCell({
  day,
  month,
  isToday,
  lookup,
}: {
  day: MonthlyDay;
  month: string;
  isToday: boolean;
  lookup: FeelingLookup;
}) {
  const logged = day.feelings.length > 0;
  const number = dayOfMonth(day.date);
  const feelings = logged ? day.feelings.map(lookup.label).join(', ') : 'no entries';
  // I6-04: how strongly, not only which. Announced in the same sentence rather than added as a
  // second label, because it qualifies the feelings rather than standing beside them.
  // `== null` rather than `=== null`: a backend that predates the dial omits the field, and an
  // absent rating and a cleared one mean the same thing to a reader.
  const intensity = day.intensity == null ? '' : `, intensity ${day.intensity}`;
  // "Today" leads, because that is the thing a reader scanning the grid is looking for.
  const description = `${isToday ? 'Today, ' : ''}${number} ${month}: ${feelings}${intensity}`;

  return (
    <td
      className={`calendar-day ${logged ? 'calendar-day--logged' : 'calendar-day--empty'}${
        isToday ? ' calendar-day--today' : ''
      }`}
    >
      {/* The hidden label carries the whole cell, so the visible parts are hidden from AT to
          avoid the day number being announced twice. */}
      <span className="visually-hidden">{description}</span>
      <span className="calendar-day__number" aria-hidden="true">
        {number}
      </span>
      <span className="calendar-day__dots" aria-hidden="true" title={description}>
        {day.feelings.map((feeling) => (
          <span
            key={feeling}
            className="calendar-day__dot"
            style={feelingDotStyle(lookup.groupKey(feeling))}
          />
        ))}
      </span>
      {/*
        A short bar rather than a number: the cell is already carrying a date and a row of dots,
        and a second digit in it reads as a count of entries. Days with no rating show nothing at
        all, so a diary where nobody uses the dial looks exactly as it did before (I6-01).
      */}
      {day.intensity != null && (
        <span className="calendar-day__intensity" aria-hidden="true">
          <span
            className="calendar-day__intensity-fill"
            style={{ width: `${(day.intensity / 5) * 100}%` }}
          />
        </span>
      )}
    </td>
  );
}
