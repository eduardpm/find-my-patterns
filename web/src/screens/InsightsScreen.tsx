import { fetchInsights } from '../api/insights';
import { ErrorBanner } from '../components/ErrorBanner';
import { PatternCard } from '../components/PatternCard';
import type { Insights } from '../domain/types';
import { useRefreshable } from '../hooks/useRefreshable';

/**
 * The Insights view (FR-007).
 *
 * Read-only by design: the screen loads `GET /insights` once and gives the user an explicit refresh
 * (FR-019) rather than polling. Nothing on this screen is computed — the patterns, their counts,
 * their direction, and the verdict that there is not enough data yet all arrive from the backend
 * (constitution Principle VII). If it isn't in the response, it isn't on this screen.
 */
export default function InsightsScreen() {
  const { data, failure, loading, refresh } = useRefreshable<Insights>(fetchInsights);

  return (
    <section className="stack" aria-busy={loading}>
      <header className="app-header">
        <h1>Insights</h1>
        <div className="row">
          {/* Always rendered so the live region exists before its text changes. */}
          <span className="muted" role="status">
            {loading ? 'Loading…' : ''}
          </span>
          <button type="button" className="btn btn--secondary" onClick={refresh}>
            Refresh insights
          </button>
        </div>
      </header>

      <ErrorBanner failure={failure} onRetry={refresh} />

      {data && <InsightsBody insights={data} />}
    </section>
  );
}

function InsightsBody({ insights }: { insights: Insights }) {
  // US4 AC3. `insufficient_data` is the backend's answer, not a conclusion drawn from the length of
  // `patterns` — the minimum-occurrence threshold lives there and must never be mirrored here.
  if (insights.insufficient_data) {
    return (
      <div className="card stack insights-empty">
        <h2>Not enough entries yet</h2>
        <p className="muted">
          Keep writing. Once a topic and a feeling show up together often enough, the pattern will
          appear here — on this screen and on your phone, identically.
        </p>
      </div>
    );
  }

  if (insights.patterns.length === 0) {
    return <p className="muted">No patterns are active right now.</p>;
  }

  return (
    <ul className="stack insights-list">
      {insights.patterns.map((pattern) => (
        <li key={pattern.id}>
          <PatternCard pattern={pattern} />
        </li>
      ))}
    </ul>
  );
}

export { InsightsScreen };
