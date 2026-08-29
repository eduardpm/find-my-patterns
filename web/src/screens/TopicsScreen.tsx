import { useCallback, useState } from 'react';
import type { ApiFailure } from '../api/client';
import { addTopicAlias, listTopics, removeTopicAlias } from '../api/topics';
import { ErrorBanner } from '../components/ErrorBanner';
import { Icon } from '../components/Icon';
import type { TopicDetail } from '../domain/types';
import { useRefreshable } from '../hooks/useRefreshable';

/**
 * The topics the diary has found, and the words the user has taught it to fold into them (A4-04).
 *
 * This screen exists because topic normalisation has a half the backend cannot decide on its own.
 * The canonical list handles what is true for everyone — a project review is work — and this
 * handles what is true for one person: "gym session" is exercise in most diaries and something
 * else entirely in a physiotherapist's. The alternative was asking the model whether two phrases
 * mean the same thing, which is exactly the judgement the constitution keeps it out of.
 *
 * Everything added here takes effect on the next recompute. No model runs, and no entry changes.
 */
export function TopicsScreen() {
  const { data, failure, loading, refresh } = useRefreshable<TopicDetail[]>(
    useCallback(() => listTopics(), []),
  );
  const [error, setError] = useState<ApiFailure | null>(null);

  return (
    <section className="stack stack--loose" aria-busy={loading}>
      <header className="page-header">
        <div className="page-header__titles">
          <span className="page-header__eyebrow">What the diary noticed</span>
          <h1>Topics</h1>
        </div>
        <div className="page-header__actions">
          <button type="button" className="btn btn--secondary" onClick={refresh}>
            <Icon name="refresh" />
            Refresh
          </button>
        </div>
      </header>

      <p className="muted">
        Add another way you write about a topic and the two are counted as one from the next time
        Insights is opened. Nothing you have written changes.
      </p>

      <ErrorBanner failure={failure ?? error} onRetry={refresh} />

      {data && data.length === 0 && (
        <div className="empty-state">
          <span className="empty-state__icon">
            <Icon name="spark" size="1.5rem" />
          </span>
          <p className="empty-state__title">No topics yet</p>
          <p>Topics appear once you have written entries the app can read them from.</p>
        </div>
      )}

      {data && data.length > 0 && (
        <ul className="topic-list">
          {data.map((topic) => (
            <TopicRow
              key={topic.id}
              topic={topic}
              onChanged={refresh}
              onError={setError}
              onClearError={() => setError(null)}
            />
          ))}
        </ul>
      )}
    </section>
  );
}

function TopicRow({
  topic,
  onChanged,
  onError,
  onClearError,
}: {
  topic: TopicDetail;
  onChanged: () => void;
  onError: (failure: ApiFailure) => void;
  onClearError: () => void;
}) {
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);

  async function add(event: React.FormEvent) {
    event.preventDefault();
    if (!draft.trim()) return;
    setBusy(true);
    onClearError();
    const result = await addTopicAlias(topic.id, draft.trim());
    setBusy(false);
    if (!result.ok) {
      onError(result.error);
      return;
    }
    setDraft('');
    onChanged();
  }

  async function remove(alias: string) {
    setBusy(true);
    onClearError();
    const result = await removeTopicAlias(topic.id, alias);
    setBusy(false);
    if (!result.ok) {
      onError(result.error);
      return;
    }
    onChanged();
  }

  return (
    <li className="card stack topic-row">
      <div className="topic-row__header">
        <h2 className="topic-row__name">{topic.name}</h2>
        <span className="muted tnum">
          {topic.entry_count} {topic.entry_count === 1 ? 'entry' : 'entries'}
        </span>
      </div>

      {topic.aliases.length > 0 && (
        <ul className="topic-row__aliases">
          {topic.aliases.map((alias) => (
            <li key={alias}>
              <span className="topic-alias">
                {alias}
                <button
                  type="button"
                  className="topic-alias__remove"
                  onClick={() => void remove(alias)}
                  disabled={busy}
                  aria-label={`Remove the alias ${alias} from ${topic.name}`}
                >
                  <Icon name="close" size="0.8em" />
                </button>
              </span>
            </li>
          ))}
        </ul>
      )}

      <form className="topic-row__form" onSubmit={add}>
        <label className="visually-hidden" htmlFor={`alias-${topic.id}`}>
          Another way you write about {topic.name}
        </label>
        <input
          id={`alias-${topic.id}`}
          className="input"
          value={draft}
          placeholder={`Another word for ${topic.name}`}
          onChange={(event) => setDraft(event.target.value)}
        />
        <button
          type="submit"
          className="btn btn--secondary btn--small"
          disabled={busy || !draft.trim()}
        >
          <Icon name="plus" size="0.9em" />
          Add
        </button>
      </form>
    </li>
  );
}

export default TopicsScreen;
