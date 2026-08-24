import type { Pattern, PatternDirection } from '../domain/types';
import { Icon, type IconName } from './Icon';

/**
 * One detected pattern.
 *
 * Constitution Principle VII: every value here is displayed as received. This component does not
 * derive `direction` from the feeling's valence, does not re-count occurrences, does not apply a
 * threshold, and does not rewrite `narrative_text` or `suggestion_text` — those are the backend's
 * words, and rewording them here would let the two clients disagree (SC-005). The only things this
 * file owns are presentational: the badge wording, its arrow, the layout, and the topic's leading
 * capital (applied in CSS, so the string itself is untouched).
 */

/**
 * Presentation only — the backend still decides *which* of these two a pattern is. Each direction
 * gets a word, an arrow and a colour rather than a colour alone: red-versus-green is exactly the
 * pair that disappears for the most common form of colour blindness (FR-027).
 */
const DIRECTION: Record<PatternDirection, { label: string; icon: IconName }> = {
  keep: { label: 'Worth keeping', icon: 'trendUp' },
  change: { label: 'Worth changing', icon: 'trendDown' },
};

interface Props {
  pattern: Pattern;
}

export function PatternCard({ pattern }: Props) {
  const topicId = `pattern-topic-${pattern.id}`;
  const direction = DIRECTION[pattern.direction];

  return (
    <article className="card stack pattern-card" aria-labelledby={topicId}>
      <div className="pattern-card__header">
        <h3 className="pattern-card__topic" id={topicId}>
          {pattern.topic}
        </h3>
        <span className={`pattern-badge pattern-badge--${pattern.direction}`}>
          <Icon name={direction.icon} size="1em" />
          {direction.label}
        </span>
      </div>

      <p className="pattern-card__narrative">{pattern.narrative_text}</p>

      {/*
        Set apart from the narrative because it is a different kind of statement: the narrative is
        what the diary says, the suggestion is what to do about it. Running them together as two
        plain paragraphs made the advice read as more findings.
      */}
      <p className="pattern-card__suggestion">
        <Icon name="spark" size="1.1em" />
        <span>{pattern.suggestion_text}</span>
      </p>

      <p className="pattern-card__footer muted">
        <span className="tnum">{pattern.occurrence_count}</span>
        <span>{pattern.occurrence_count === 1 ? 'occurrence' : 'occurrences'}</span>
      </p>
    </article>
  );
}
