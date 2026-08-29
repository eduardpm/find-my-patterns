import { Link } from 'react-router-dom';
import type { PatternEcho } from '../domain/types';
import { Icon } from './Icon';

/**
 * What the diary already says about what was just written (I4).
 *
 * Shown **after** the entry is saved and never during composition, which is the whole design: an
 * app that said "you usually feel anxious about meetings" while someone was still describing the
 * meeting would be shaping the evidence it then counts (I4-02).
 *
 * It states an observation and stops. No prediction, no advice, and nothing about how the user
 * feels today — the sentence is the pattern card's own sentence, unchanged (I4-03). Dismissing it
 * affects nothing but this panel (I4-07).
 */

interface Props {
  echoes: PatternEcho[];
  onDismiss: () => void;
}

export function PatternEchoPanel({ echoes, onDismiss }: Props) {
  if (echoes.length === 0) return null;

  return (
    <aside className="card stack echo-panel" aria-labelledby="echo-heading">
      <div className="echo-panel__header">
        <h2 id="echo-heading" className="section-heading">
          <Icon name="spark" size="1em" />
          You have written about this before
        </h2>
        <button
          type="button"
          className="btn btn--ghost btn--small"
          onClick={onDismiss}
          aria-label="Dismiss"
        >
          <Icon name="close" size="0.9em" />
        </button>
      </div>

      <ul className="echo-panel__list">
        {echoes.map((echo) => (
          <li className="echo-panel__item" key={echo.pattern_id}>
            <p className="echo-panel__narrative">{echo.narrative_text}</p>
            <Link className="echo-panel__link" to="/app/insights">
              <Icon name="layers" size="0.95em" />
              See the entries behind this
            </Link>
          </li>
        ))}
      </ul>
    </aside>
  );
}
