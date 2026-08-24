import type { CSSProperties } from 'react';
import type { MonthlyDay } from '../domain/types';

interface Props {
  /** The month being shown, `YYYY-MM`. Used only for the caption and cell labels. */
  month: string;
  /** One item per day of the month, exactly as the backend returned them. */
  days: MonthlyDay[];
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
 * Presentational only: the feeling *key* comes from the backend, and this turns it into something
 * readable. The set of keys is never assumed — an unknown key still renders, just with the outline
 * colour (see `feelingDotStyle`).
 */
export function feelingLabel(key: string): string {
  const words = key.split('_').filter(Boolean);
  if (words.length === 0) return key;
  return words.map((w) => w[0].toUpperCase() + w.slice(1)).join(' ');
}

/**
 * The per-feeling accent from tokens.css, falling back to the neutral outline for any key this
 * client has no colour for. Colour is decoration here — every dot is also named in text, because
 * FR-027 forbids conveying meaning by colour alone.
 */
export function feelingDotStyle(key: string): CSSProperties {
  return { backgroundColor: `var(--feeling-${key}, var(--color-outline))` };
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
export function CalendarGrid({ month, days }: Props) {
  const label = monthLabel(month);
  const today = todayIso();

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
                <DayCell key={day.date} day={day} month={label} isToday={day.date === today} />
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

function DayCell({ day, month, isToday }: { day: MonthlyDay; month: string; isToday: boolean }) {
  const logged = day.feelings.length > 0;
  const number = dayOfMonth(day.date);
  const feelings = logged ? day.feelings.map(feelingLabel).join(', ') : 'no entries';
  // "Today" leads, because that is the thing a reader scanning the grid is looking for.
  const description = `${isToday ? 'Today, ' : ''}${number} ${month}: ${feelings}`;

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
          <span key={feeling} className="calendar-day__dot" style={feelingDotStyle(feeling)} />
        ))}
      </span>
    </td>
  );
}
