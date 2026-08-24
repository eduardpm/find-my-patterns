import { useCallback, useState } from 'react';
import { fetchMonthlySummary } from '../api/monthlySummary';
import {
  CalendarGrid,
  feelingDotStyle,
  feelingLabel,
  monthLabel,
} from '../components/CalendarGrid';
import { ErrorBanner } from '../components/ErrorBanner';
import { Icon } from '../components/Icon';
import { useRefreshable } from '../hooks/useRefreshable';
import type { MonthlySummary } from '../domain/types';

/** The month the user is in right now — local, because "this month" is a local-calendar question. */
function currentMonth(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
}

/** Month arithmetic on `YYYY-MM`, done in months-since-year-zero so December wraps correctly. */
function shiftMonth(month: string, delta: number): string {
  const year = Number(month.slice(0, 4));
  const index = year * 12 + (Number(month.slice(5, 7)) - 1) + delta;
  return `${String(Math.floor(index / 12)).padStart(4, '0')}-${String((index % 12) + 1).padStart(2, '0')}`;
}

/**
 * The monthly view (US5, FR-008).
 *
 * SC-006 wants the whole month's breakdown on one screen, so the grid, the per-feeling totals and
 * the daily average are all here — no drill-down, no second route.
 *
 * The month is local state rather than a route parameter: FR-024 keeps diary content out of URLs,
 * and while a month is not content, there is no reason to put it there either.
 */
export function MonthlyCalendarScreen() {
  const [month, setMonth] = useState(currentMonth);

  return (
    <div className="stack stack--loose">
      <header className="page-header">
        <div className="page-header__titles">
          <span className="page-header__eyebrow">A month at a glance</span>
          <h1>Monthly overview</h1>
        </div>
      </header>

      {/*
        A three-slot stepper — control, label, control — rather than a flex row of two wide labelled
        buttons. The labelled version wrapped on a phone and dropped "Next month" onto its own line
        below "Previous month", which stopped reading as a pair. The arrows keep their names for
        assistive tech and as a pointer tooltip; only the visible text is dropped.
      */}
      <div className="month-switcher">
        <button
          type="button"
          className="btn btn--secondary btn--icon"
          onClick={() => setMonth((m) => shiftMonth(m, -1))}
        >
          <Icon name="chevronLeft" title="Previous month" />
        </button>
        <h2 className="month-switcher__label" aria-live="polite">
          {monthLabel(month)}
        </h2>
        <button
          type="button"
          className="btn btn--secondary btn--icon"
          onClick={() => setMonth((m) => shiftMonth(m, 1))}
        >
          <Icon name="chevronRight" title="Next month" />
        </button>
      </div>

      {/*
        `key` remounts the panel on every month change, which is what re-runs its initial load.
        `useRefreshable` deliberately fetches once and then only on an explicit refresh (FR-019),
        so a changing `load` closure alone would not refetch.
      */}
      <MonthPanel key={month} month={month} />
    </div>
  );
}

function MonthPanel({ month }: { month: string }) {
  const load = useCallback(() => fetchMonthlySummary(month), [month]);
  const { data, failure, loading, refresh } = useRefreshable(load);

  return (
    <div className="stack">
      <ErrorBanner failure={failure} onRetry={refresh} />

      {loading && !data && (
        <p className="muted" role="status">
          Loading {monthLabel(month)}…
        </p>
      )}

      {data && (
        <>
          <div className="card calendar-card">
            <CalendarGrid month={data.month} days={data.days} />
          </div>
          <MonthTotals summary={data} />
          <div className="row">
            <button type="button" className="btn btn--text" onClick={refresh}>
              <Icon name="refresh" />
              Refresh
            </button>
          </div>
        </>
      )}
    </div>
  );
}

/**
 * Every number below is printed exactly as the backend sent it.
 *
 * This is constitution Principle VII at its sharpest: `days[].feelings` holds the *distinct*
 * feelings of a day, so adding those up would undercount a day with two "happy" entries and
 * silently disagree with the phone. The average is likewise the server's — it divides by days
 * *elapsed*, a rule this client has no business knowing. Not even rounding is applied, so what is
 * on screen is provably the served value (SC-005, and `tests/monthlyCalendar.test.tsx` guards it).
 */
function MonthTotals({ summary }: { summary: MonthlySummary }) {
  const totals = Object.entries(summary.totals_by_feeling);

  return (
    <section className="card stack" aria-labelledby="month-totals-heading">
      <h3 id="month-totals-heading">This month</h3>

      <p className="summary-average">
        {/*
          Formatted to one decimal to match the Android app's `%.1f` — SC-005 requires both clients
          to show the *same* number, and "0.3" beside "0.32142857142857145" is a visible
          disagreement even though the underlying value is identical. Rounding for display is
          presentation, which Principle VII leaves to the client; the value itself is still the
          server's and is never recomputed here.
        */}
        <strong className="summary-average__value">
          {summary.average_entries_per_day.toFixed(1)}
        </strong>
        <span className="muted">entries per day, on average</span>
      </p>

      {totals.length === 0 ? (
        <p className="muted">No feelings logged this month.</p>
      ) : (
        <ul className="totals">
          {totals.map(([feeling, count]) => (
            <li key={feeling} className="totals__item">
              <span className="feeling-dot" style={feelingDotStyle(feeling)} aria-hidden="true" />
              <span className="totals__label">{feelingLabel(feeling)}</span>
              <span className="totals__count">{count}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

export default MonthlyCalendarScreen;
