import type { Entry } from '../domain/types';

interface Props {
  /** What the user wrote and tried to save. Never discarded without them saying so (FR-023). */
  mine: string;
  /** The entry as actually stored, from the 409 body. `null` when it was deleted elsewhere. */
  current: Entry | null;
  onRetry: (mine: string, currentVersion: number) => void;
  onDiscard: () => void;
  onCarryAcross: (mine: string) => void;
}

/**
 * Shown when a save was rejected because the entry changed somewhere else (FR-011 → FR-023).
 *
 * The whole design rule here is "reject and preserve": the user's text stays on screen next to the
 * stored version, and they choose. Losing what someone just typed into a *diary* is the worst
 * failure this app can have, and auto-merging would be worse still — it would invent text they
 * never wrote. So there is deliberately no merge button and no automatic winner.
 *
 * Rendered as a presentational component with callbacks so the resolution logic stays testable
 * without a router or a live backend.
 */
export function ConflictView({ mine, current, onRetry, onDiscard, onCarryAcross }: Props) {
  const wasDeleted = current === null;

  return (
    <div className="stack">
      <h1>This entry changed elsewhere</h1>

      <div className="error-banner" role="alert">
        {wasDeleted
          ? 'This entry was deleted on another device, so there’s nothing to save it back to. Your writing is below — copy anything you want to keep.'
          : 'Your view was out of date, so nothing was overwritten. Here’s what you wrote and what’s currently saved.'}
      </div>

      <div className="conflict-pair">
        <section className="stack" aria-labelledby="conflict-mine">
          <h2 id="conflict-mine">What you wrote</h2>
          <blockquote className="card entry-card__text">{mine}</blockquote>
        </section>

        {!wasDeleted && (
          <section className="stack" aria-labelledby="conflict-theirs">
            <h2 id="conflict-theirs">What’s saved now</h2>
            <blockquote className="card entry-card__text">{current.raw_text}</blockquote>
          </section>
        )}
      </div>

      <div className="row">
        {!wasDeleted && (
          <button
            type="button"
            className="btn"
            // Retry against the version from the 409 body, which the contract guarantees is
            // immediately reusable — not the stale one this screen was reached with.
            onClick={() => onRetry(mine, current.version)}
          >
            Keep mine (overwrite)
          </button>
        )}
        <button type="button" className="btn btn--secondary" onClick={() => onCarryAcross(mine)}>
          Copy mine into the editor
        </button>
        <button type="button" className="btn btn--text" onClick={onDiscard}>
          Discard mine
        </button>
      </div>
    </div>
  );
}
