import { useCallback } from 'react';
import { Link } from 'react-router-dom';
import { listEntries } from '../api/entries';
import { fetchFeelings } from '../api/feelings';
import { EntryCard } from '../components/EntryCard';
import { ErrorBanner } from '../components/ErrorBanner';
import { Icon } from '../components/Icon';
import type { Entry, Feeling } from '../domain/types';
import { useRefreshable } from '../hooks/useRefreshable';

function todayIso(): string {
  const now = new Date();
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}

/** "Sunday, 24 August" in the reader's locale. Presentation, so it belongs here. */
function longDate(iso: string): string {
  const parsed = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) return iso;
  return new Intl.DateTimeFormat(undefined, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  }).format(parsed);
}

/**
 * Today's entries, newest work at the bottom the way a diary reads.
 *
 * The refresh button is a requirement, not a convenience: FR-019 rules out live updates, so this is
 * how a change made on the phone becomes visible here. Seeing stale data is expected; acting on it
 * is made safe by the conflict protection in FR-011 rather than by polling.
 *
 * The h1 stays the single word "Today" and the date rides above it as an eyebrow. Two reasons: the
 * heading is what a screen-reader user hears when they jump by landmark, and it is what the smoke
 * test navigates by — neither wants a date glued to it.
 */
export function TodayScreen() {
  const date = todayIso();
  const entries = useRefreshable<Entry[]>(useCallback(() => listEntries(date), [date]));
  const { data: feelings } = useRefreshable<Feeling[]>(useCallback(() => fetchFeelings(), []));

  const list = entries.data ?? [];
  const settled = !entries.loading && !entries.failure;

  return (
    <div className="stack stack--loose">
      <header className="page-header">
        <div className="page-header__titles">
          <span className="page-header__eyebrow">{longDate(date)}</span>
          <h1>Today</h1>
        </div>
        <div className="page-header__actions">
          <button type="button" className="btn btn--secondary" onClick={entries.refresh}>
            <Icon name="refresh" />
            Refresh
          </button>
          <Link to="/app/new" className="btn">
            <Icon name="plus" />
            Write an entry
          </Link>
        </div>
      </header>

      <ErrorBanner failure={entries.failure} onRetry={entries.refresh} />

      {entries.loading && (
        <p className="muted" role="status">
          Loading…
        </p>
      )}

      {settled && list.length === 0 && (
        <div className="empty-state">
          <span className="empty-state__icon">
            <Icon name="spark" size="1.5rem" />
          </span>
          <p className="empty-state__title">Nothing yet today</p>
          <p>Whatever just happened is worth a line. A sentence counts.</p>
          <Link to="/app/new" className="btn">
            <Icon name="plus" />
            Write an entry
          </Link>
        </div>
      )}

      {/*
        The count is announced rather than merely displayed, and it names what changed instead of
        being a bare number, so a refresh that pulls in an entry written on the phone is legible
        without sight.
      */}
      <div className="stack" aria-live="polite">
        {list.length > 0 && (
          <p className="eyebrow">
            {list.length} {list.length === 1 ? 'entry' : 'entries'} today
          </p>
        )}
        <ul className="entry-list">
          {list.map((entry) => (
            <li key={entry.id}>
              <EntryCard entry={entry} feelings={feelings ?? []} />
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
