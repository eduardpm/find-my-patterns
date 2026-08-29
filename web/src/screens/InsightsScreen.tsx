import { useCallback, useState } from 'react';
import { acknowledgeWithdrawals, fetchInsights, fetchWhenInsights } from '../api/insights';
import { ErrorBanner } from '../components/ErrorBanner';
import { Icon } from '../components/Icon';
import { PatternCard } from '../components/PatternCard';
import { WhenPanel } from '../components/WhenPanel';
import { WithdrawalNotice } from '../components/WithdrawalNotice';
import type { Insights, Pattern, WhenInsights } from '../domain/types';
import { useRefreshable } from '../hooks/useRefreshable';

/**
 * The Insights view (FR-007).
 *
 * Read-only by design: the screen loads `GET /insights` once and gives the user an explicit refresh
 * (FR-019) rather than polling. Nothing on this screen is computed — the patterns, their counts,
 * their lift, their active/historical label, the withdrawal notices and the verdict that there is
 * not enough data yet all arrive from the backend (constitution Principle VII). If it isn't in the
 * response, it isn't on this screen.
 *
 * The order of the page is the order of the argument: what changed since you last looked, then what
 * is happening now, then what used to happen, then when it happens.
 */
export default function InsightsScreen() {
  const { data, failure, loading, refresh } = useRefreshable<Insights>(fetchInsights);
  const when = useRefreshable<WhenInsights>(useCallback(() => fetchWhenInsights(), []));

  const refreshAll = useCallback(() => {
    refresh();
    when.refresh();
  }, [refresh, when]);

  return (
    <section className="stack stack--loose" aria-busy={loading}>
      <header className="page-header">
        <div className="page-header__titles">
          <span className="page-header__eyebrow">What keeps happening</span>
          <h1>Insights</h1>
        </div>
        <div className="page-header__actions">
          {/* Always rendered so the live region exists before its text changes. */}
          <span className="muted" role="status">
            {loading ? 'Loading…' : ''}
          </span>
          <button type="button" className="btn btn--secondary" onClick={refreshAll}>
            <Icon name="refresh" />
            Refresh insights
          </button>
        </div>
      </header>

      <ErrorBanner failure={failure} onRetry={refreshAll} />

      {data && <InsightsBody insights={data} onAcknowledged={refresh} />}
      {when.data && (
        <section className="card stack when-panel" aria-labelledby="when-heading">
          <h2 id="when-heading" className="section-heading">
            When it happens
          </h2>
          <WhenPanel insights={when.data} />
        </section>
      )}
    </section>
  );
}

function InsightsBody({
  insights,
  onAcknowledged,
}: {
  insights: Insights;
  onAcknowledged: () => void;
}) {
  const active = insights.patterns.filter((pattern) => pattern.status === 'active');
  const historical = insights.patterns.filter((pattern) => pattern.status === 'historical');

  return (
    <div className="stack stack--loose">
      {/*
        A2-03: withdrawals come first, because the one thing a user must never have to notice for
        themselves is a pattern they were told about quietly going away.
      */}
      <WithdrawalsSection insights={insights} onAcknowledged={onAcknowledged} />

      {insights.insufficient_data ? (
        <div className="empty-state">
          <span className="empty-state__icon">
            <Icon name="trendUp" size="1.5rem" />
          </span>
          <p className="empty-state__title">Not enough entries yet</p>
          <p>
            Keep writing. Once a topic and a feeling show up together often enough — at least{' '}
            {insights.constants.min_occurrence_threshold} times in the last{' '}
            {insights.constants.recency_window_days} days — the pattern will appear here, on this
            screen and on your phone, identically.
          </p>
        </div>
      ) : (
        <>
          <PatternList
            heading="Happening now"
            patterns={active}
            insights={insights}
            emptyText={`Nothing is repeating often enough in the last ${insights.constants.recency_window_days} days to call it a pattern right now.`}
          />
          {historical.length > 0 && (
            <PatternList
              heading="No longer recent"
              patterns={historical}
              insights={insights}
              emptyText=""
              lede="These held often enough to count once. They are kept, and clearly marked, rather than quietly dropped."
            />
          )}
        </>
      )}
    </div>
  );
}

function PatternList({
  heading,
  patterns,
  insights,
  emptyText,
  lede,
}: {
  heading: string;
  patterns: Pattern[];
  insights: Insights;
  emptyText: string;
  lede?: string;
}) {
  const id = `insights-${heading.replace(/\s+/g, '-').toLowerCase()}`;
  return (
    <section className="stack" aria-labelledby={id}>
      <h2 id={id} className="section-heading">
        {heading}
      </h2>
      {lede && <p className="muted">{lede}</p>}
      {patterns.length === 0 ? (
        <div className="empty-state">
          <span className="empty-state__icon">
            <Icon name="spark" size="1.5rem" />
          </span>
          <p className="empty-state__title">No active patterns</p>
          <p>{emptyText}</p>
        </div>
      ) : (
        <ul className="insights-list">
          {patterns.map((pattern) => (
            <li key={pattern.id}>
              <PatternCard pattern={pattern} constants={insights.constants} />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

/**
 * "2 patterns were withdrawn since you last looked" (A2-07).
 *
 * Acknowledging is an explicit button rather than a side effect of the screen loading: if opening
 * Insights cleared the flag, whichever device the user opened first would clear it for the other,
 * and the phone would then show a different number from the browser for the same diary (C-02).
 */
function WithdrawalsSection({
  insights,
  onAcknowledged,
}: {
  insights: Insights;
  onAcknowledged: () => void;
}) {
  const [working, setWorking] = useState(false);
  if (insights.withdrawals.length === 0) return null;

  async function acknowledge() {
    setWorking(true);
    await acknowledgeWithdrawals();
    setWorking(false);
    onAcknowledged();
  }

  return (
    <section className="card stack withdrawals" aria-labelledby="withdrawals-heading">
      <div className="withdrawals__header">
        <h2 id="withdrawals-heading" className="section-heading">
          Recently withdrawn
        </h2>
        {insights.new_withdrawal_count > 0 && (
          <span className="withdrawals__count">
            <span className="tnum">{insights.new_withdrawal_count}</span>{' '}
            {insights.new_withdrawal_count === 1 ? 'pattern' : 'patterns'} since you last looked
          </span>
        )}
      </div>
      <ul className="withdrawals__list">
        {insights.withdrawals.map((withdrawal) => (
          <WithdrawalNotice key={withdrawal.id} withdrawal={withdrawal} />
        ))}
      </ul>
      {insights.new_withdrawal_count > 0 && (
        <div>
          <button
            type="button"
            className="btn btn--ghost btn--small"
            onClick={acknowledge}
            disabled={working}
          >
            <Icon name="check" size="1em" />
            Got it
          </button>
        </div>
      )}
    </section>
  );
}

export { InsightsScreen };
