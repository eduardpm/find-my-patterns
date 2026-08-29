import type { WhenBucket, WhenInsights } from '../domain/types';
import { Icon } from './Icon';

/**
 * "When am I worst?", answered from entries the user already wrote (I5).
 *
 * Two rules shape everything here, and both come from the backend rather than from this file:
 *
 *  - **A thin bucket says so.** One Monday is an anecdote. The backend marks a bucket
 *    `sufficient: false` and sends no average at all, and this component prints "not enough yet"
 *    rather than drawing a bar of length zero — which would read as a very good Monday (I5-02).
 *  - **These are time patterns, not causes.** Nothing here says a weekday *makes* anyone feel
 *    anything (I5-06). It says what the diary contains.
 *
 * The bar width is the only computation on this page, and it is presentation: mapping a −1…+1
 * average onto a track. The average itself is the backend's.
 */

/** −1 … +1 onto 0 … 100% of the track, with the midpoint at 50%. */
const offset = (value: number): number => ((value + 1) / 2) * 100;

interface Props {
  insights: WhenInsights;
}

export function WhenPanel({ insights }: Props) {
  if (insights.total_entries === 0) {
    return (
      <p className="muted">
        Nothing in the last {insights.window_days} days yet — this fills in as you write.
      </p>
    );
  }

  return (
    <div className="stack">
      <p className="muted when-panel__lede">
        Across the {insights.total_entries} {insights.total_entries === 1 ? 'entry' : 'entries'} you
        confirmed in the last {insights.window_days} days. These are times, not causes.
      </p>

      <WhenGroup
        title="By day of the week"
        buckets={insights.weekdays}
        best={insights.best_weekday}
        worst={insights.worst_weekday}
        minimum={insights.min_bucket_entries}
      />
      <WhenGroup
        title="By time of day"
        buckets={insights.times_of_day}
        best={insights.best_time_of_day}
        worst={insights.worst_time_of_day}
        minimum={insights.min_bucket_entries}
      />
    </div>
  );
}

function WhenGroup({
  title,
  buckets,
  best,
  worst,
  minimum,
}: {
  title: string;
  buckets: WhenBucket[];
  best: string | null;
  worst: string | null;
  minimum: number;
}) {
  return (
    <section className="when-group">
      <h3 className="when-group__title">{title}</h3>
      <ul className="when-list">
        {buckets.map((bucket) => (
          <li className="when-row" key={bucket.key}>
            <span className="when-row__label">
              {bucket.label}
              {/* I5-05. Named in words as well as marked, so the highlight survives greyscale. */}
              {bucket.key === best && (
                <span className="when-row__tag when-row__tag--best">Best</span>
              )}
              {bucket.key === worst && (
                <span className="when-row__tag when-row__tag--worst">Hardest</span>
              )}
            </span>

            {bucket.sufficient && bucket.average_valence !== null ? (
              <span className="when-row__track" aria-hidden="true">
                <span className="when-row__zero" />
                <span
                  className={`when-row__marker ${
                    bucket.average_valence < 0 ? 'when-row__marker--low' : 'when-row__marker--high'
                  }`}
                  style={{ left: `${offset(bucket.average_valence)}%` }}
                />
              </span>
            ) : (
              <span className="when-row__insufficient muted">
                <Icon name="warning" size="0.95em" />
                fewer than {minimum} entries
              </span>
            )}

            <span className="when-row__count muted tnum">
              {bucket.sufficient && bucket.average_valence !== null
                ? `${bucket.average_valence > 0 ? '+' : ''}${bucket.average_valence.toFixed(2)}`
                : ''}
              <span className="when-row__entries">
                {bucket.entry_count} {bucket.entry_count === 1 ? 'entry' : 'entries'}
              </span>
            </span>
          </li>
        ))}
      </ul>
    </section>
  );
}
