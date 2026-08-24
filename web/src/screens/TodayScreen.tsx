import { useCallback } from 'react';
import { Link } from 'react-router-dom';
import { listEntries } from '../api/entries';
import { fetchFeelings } from '../api/feelings';
import { EntryCard } from '../components/EntryCard';
import { ErrorBanner } from '../components/ErrorBanner';
import type { Entry, Feeling } from '../domain/types';
import { useRefreshable } from '../hooks/useRefreshable';

function todayIso(): string {
  const now = new Date();
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}

/**
 * Today's entries, newest work at the bottom the way a diary reads.
 *
 * The refresh button is a requirement, not a convenience: FR-019 rules out live updates, so this is
 * how a change made on the phone becomes visible here. Seeing stale data is expected; acting on it
 * is made safe by the conflict protection in FR-011 rather than by polling.
 */
export function TodayScreen() {
  const date = todayIso();
  const entries = useRefreshable<Entry[]>(useCallback(() => listEntries(date), [date]));
  const { data: feelings } = useRefreshable<Feeling[]>(useCallback(() => fetchFeelings(), []));

  const list = entries.data ?? [];

  return (
    <div className="stack">
      <div className="app-header">
        <h1>Today</h1>
        <button type="button" className="btn btn--text" onClick={entries.refresh}>
          Refresh
        </button>
      </div>

      <ErrorBanner failure={entries.failure} onRetry={entries.refresh} />

      <Link to="/app/new" className="btn">
        Write an entry
      </Link>

      {entries.loading && <p className="muted">Loading…</p>}

      {!entries.loading && !entries.failure && list.length === 0 && (
        <p className="muted">Nothing yet today. Whatever just happened is worth a line.</p>
      )}

      <div className="stack" aria-live="polite">
        {list.map((entry) => (
          <EntryCard key={entry.id} entry={entry} feelings={feelings ?? []} />
        ))}
      </div>

      {list.length > 0 && (
        <p className="muted">
          {list.length} {list.length === 1 ? 'entry' : 'entries'} today
        </p>
      )}
    </div>
  );
}
