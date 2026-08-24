import type { Pattern, PatternDirection } from '../domain/types';

/**
 * One detected pattern.
 *
 * Constitution Principle VII: every value here is displayed as received. This component does not
 * derive `direction` from the feeling's valence, does not re-count occurrences, does not apply a
 * threshold, and does not rewrite `narrative_text` or `suggestion_text` — those are the backend's
 * words, and rewording them here would let the two clients disagree (SC-005). The only things this
 * file owns are presentational: the pill wording, the layout, and the topic's leading capital
 * (applied in CSS, so the string itself is untouched).
 */

/** Presentation only — the backend still decides *which* of these two a pattern is. */
const DIRECTION_LABEL: Record<PatternDirection, string> = {
  keep: 'Worth keeping',
  change: 'Worth changing',
};

interface Props {
  pattern: Pattern;
}

export function PatternCard({ pattern }: Props) {
  const topicId = `pattern-topic-${pattern.id}`;

  return (
    <article className="card stack pattern-card" aria-labelledby={topicId}>
      <div className="pattern-card__header">
        <h3 className="pattern-card__topic" id={topicId}>
          {pattern.topic}
        </h3>
        <span className={`pattern-badge pattern-badge--${pattern.direction}`}>
          {DIRECTION_LABEL[pattern.direction]}
        </span>
      </div>

      <p className="pattern-card__narrative">{pattern.narrative_text}</p>

      <p className="pattern-card__suggestion">{pattern.suggestion_text}</p>

      <p className="muted">
        {pattern.occurrence_count} {pattern.occurrence_count === 1 ? 'occurrence' : 'occurrences'}
      </p>
    </article>
  );
}
