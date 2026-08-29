import { useId, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  recencyWindowPhrase,
  type EngineConstants,
  type Pattern,
  type PatternDirection,
  type PatternEvidence,
} from '../domain/types';
import { Icon, type IconName } from './Icon';

/**
 * One detected pattern, and the entries behind it.
 *
 * Constitution Principle VII: every value here is displayed as received. This component does not
 * derive `direction` from the feeling's valence, does not re-count occurrences, does not apply a
 * threshold, does not compute a rate or a lift, and does not rewrite `narrative_text` — those are
 * the backend's numbers and words, and reworking them here would let the two clients disagree
 * (SC-005/C-02). The evidence trail is rendered exactly as sent, unfiltered and unsorted (A1-10).
 *
 * What this file does own is presentation: which badge, which colour, what opens on a click, and
 * the topic's leading capital — applied in CSS, so the string itself is untouched.
 */

// Presentation only — the backend still decides *which* of these a pattern is (P0-2). Each of the
// two shown badges gets a word, an arrow and a colour rather than a colour alone: red-versus-green
// is exactly the pair that disappears for the most common form of colour blindness (FR-027).
// `'none'` (a neutral-valence feeling — no positive signal to reinforce, no negative one to
// discourage) has no entry here on purpose: it is not a third badge, it is no badge, matching the
// mobile client's `patternBadgeFor`. Falling back to `DIRECTION.change` for it — as this used to —
// is the exact defect P0-2 removes: a neutral pattern reading "Worth changing" with no negative
// signal behind it.
const DIRECTION: Record<'keep' | 'change', { label: string; icon: IconName }> = {
  keep: { label: 'Worth keeping', icon: 'trendUp' },
  change: { label: 'Worth changing', icon: 'trendDown' },
};

/**
 * Which badge, if any, a pattern card shows for `direction` (P0-2).
 *
 * The single place this decision is made on the web client, kept separately testable and mirroring
 * `patternBadgeFor` in `mobile/lib/features/insights/pattern_card.dart`. It never re-derives
 * keep/change from the pattern's kind or feeling; the backend owns that (`badgeDirectionFor` in
 * `backend/src/insights/patterns.service.ts`) — this only turns the resolved value into "show no
 * badge" vs "show this one". Since P0-6, `direction` already accounts for an undefined or
 * below-threshold lift too (the backend folds that into the same `'none'` this function already
 * handled for a neutral valence), so nothing here re-checks `pattern.lift` — that would be this
 * client disagreeing with the backend about the same diary.
 */
function directionBadge(direction: PatternDirection): { label: string; icon: IconName } | null {
  return direction === 'none' ? null : DIRECTION[direction];
}

const percent = (rate: number | null): string =>
  rate === null ? '—' : `${Math.round(rate * 100)}%`;

interface Props {
  pattern: Pattern;
  constants: EngineConstants;
}

export function PatternCard({ pattern, constants }: Props) {
  const topicId = useId();
  const evidenceId = useId();
  const [showEvidence, setShowEvidence] = useState(false);
  const badge = directionBadge(pattern.direction);
  const isInverse = pattern.kind === 'inverse';
  const isHistorical = pattern.status === 'historical';

  return (
    <article
      className={[
        'card',
        'stack',
        'pattern-card',
        `pattern-card--${pattern.kind}`,
        isHistorical ? 'pattern-card--historical' : '',
        pattern.is_strong ? 'pattern-card--strong' : '',
      ]
        .filter(Boolean)
        .join(' ')}
      aria-labelledby={topicId}
    >
      <div className="pattern-card__header">
        <div className="pattern-card__title">
          <h3 className="pattern-card__topic" id={topicId}>
            {pattern.topic}
          </h3>
          {/*
            The inverse card is a different claim about the same table — the feeling went with the
            topic's *absence* — so it says so in words rather than relying on a tint (I1-03).
          */}
          {isInverse && <span className="pattern-tag pattern-tag--inverse">Without it</span>}
          {isHistorical && (
            <span className="pattern-tag pattern-tag--historical">
              <Icon name="clock" size="0.95em" />
              Historical
            </span>
          )}
          {pattern.is_strong && <span className="pattern-tag pattern-tag--strong">Strong</span>}
        </div>
        {/*
          A neutral-valence pattern (P0-2) carries no badge at all — neither colour has anything
          to say about it — so nothing renders here rather than defaulting to either one.
        */}
        {badge && (
          <span className={`pattern-badge pattern-badge--${pattern.direction}`}>
            <Icon name={badge.icon} size="1em" />
            {badge.label}
          </span>
        )}
      </div>

      <p className="pattern-card__narrative">{pattern.narrative_text}</p>

      {/*
        The strength figures, stated on the card itself. C-05: a user must never have to trust a
        label without the count that produced it — and "3 times" means nothing until you know how
        often the feeling turns up anyway, which is what the base rate is here for.
      */}
      <dl className="pattern-stats">
        <div className="pattern-stats__item">
          <dt>{isInverse ? `Without ${pattern.topic}` : `With ${pattern.topic}`}</dt>
          <dd className="tnum">
            {percent(pattern.present_rate)}
            <span className="pattern-stats__raw">
              {pattern.present_count}/{pattern.present_total}
            </span>
          </dd>
        </div>
        <div className="pattern-stats__item">
          <dt>{isInverse ? `With ${pattern.topic}` : `Without ${pattern.topic}`}</dt>
          <dd className="tnum">
            {percent(pattern.absent_rate)}
            <span className="pattern-stats__raw">
              {pattern.absent_count}/{pattern.absent_total}
            </span>
          </dd>
        </div>
        <div className="pattern-stats__item">
          <dt>Usual rate</dt>
          <dd className="tnum">{percent(pattern.base_rate)}</dd>
        </div>
        <div className="pattern-stats__item">
          <dt>Lift</dt>
          <dd className="tnum">{pattern.lift === null ? '—' : `${pattern.lift.toFixed(1)}×`}</dd>
        </div>
      </dl>

      {/* A3-02/A3-05: where a number could not be computed, the reason is stated in its place. */}
      {pattern.comparison_note && (
        <p className="pattern-note pattern-note--comparison">{pattern.comparison_note}</p>
      )}

      {pattern.historical_note && (
        <p className="pattern-note pattern-note--historical">
          <Icon name="clock" size="1em" />
          <span>{pattern.historical_note}</span>
        </p>
      )}

      {/*
        I2-07: a confounder annotates a pattern, it never hides one. Withholding the evidence
        would contradict the app's own reason for existing.
      */}
      {pattern.confounders.map((confounder) => (
        <p className="pattern-note pattern-note--confounder" key={confounder.topic}>
          <Icon name="link" size="1em" />
          <span>{confounder.note}</span>
        </p>
      ))}

      {/*
        Set apart from the narrative because it is a different kind of statement: the narrative is
        what the diary says, the suggestion is what to do about it. Running them together as two
        plain paragraphs made the advice read as more findings.

        P0-6: no badge means no tip either. A badge-less card — a neutral feeling (P0-2) or, as of
        P0-6, a lift the card itself prints as "—" — has nothing to back advice with, so the strip
        stays out rather than offering it anyway. The narrative, the figures and the notes above are
        unaffected; only this closing suggestion goes quiet.
      */}
      {badge && (
        <p className="pattern-card__suggestion">
          <Icon name="spark" size="1.1em" />
          <span>{pattern.suggestion_text}</span>
        </p>
      )}

      <div className="pattern-card__footer">
        <p className="muted pattern-card__counts">
          <span className="tnum">{pattern.occurrence_count}</span>
          <span>
            {pattern.occurrence_count === 1 ? 'occurrence' : 'occurrences'}{' '}
            {recencyWindowPhrase(constants.recency_window_days)}
          </span>
          {pattern.lifetime_count !== pattern.occurrence_count && (
            <span className="muted">
              · <span className="tnum">{pattern.lifetime_count}</span> in total
            </span>
          )}
        </p>

        {/*
          A1-05: the evidence opens from the card itself. The count on the button is the pattern's
          own count, because the backend guarantees they are the same number (A1-02) — if they ever
          disagreed on screen, that would be worth seeing rather than papering over.
        */}
        <button
          type="button"
          className="btn btn--ghost btn--small"
          onClick={() => setShowEvidence((open) => !open)}
          aria-expanded={showEvidence}
          aria-controls={evidenceId}
        >
          <Icon name="layers" size="1em" />
          {showEvidence ? 'Hide the entries' : `Show the ${pattern.evidence.length} entries`}
        </button>
      </div>

      {showEvidence && (
        <ul className="evidence-trail" id={evidenceId}>
          {pattern.evidence.length === 0 && (
            <li className="evidence-trail__empty muted">
              Nothing {recencyWindowPhrase(constants.recency_window_days)}. This pattern is built on
              older entries.
            </li>
          )}
          {pattern.evidence.map((entry) => (
            <EvidenceRow key={entry.entry_id} entry={entry} />
          ))}
        </ul>
      )}
    </article>
  );
}

/** One supporting entry. A1-06: openable in the normal entry flow, straight from the trail. */
function EvidenceRow({ entry }: { entry: PatternEvidence }) {
  return (
    <li className="evidence-trail__item">
      <Link className="evidence-trail__link" to={`/app/entry/${entry.entry_id}`}>
        <span className="evidence-trail__date tnum">{entry.entry_date}</span>
        <span className="evidence-trail__text">{entry.raw_text}</span>
        <span className="evidence-trail__feelings">
          {entry.feeling_keys.map((key) => (
            <span className="evidence-trail__feeling" key={key}>
              {key}
            </span>
          ))}
        </span>
      </Link>
    </li>
  );
}
