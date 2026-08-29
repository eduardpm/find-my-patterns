import { useId } from 'react';
import type { Feeling } from '../domain/types';
import { Icon } from './Icon';

/**
 * The optional dial, one row per feeling on the entry (I6).
 *
 * Four things about it are requirements rather than taste:
 *
 *  - **It is optional, and every row defaults to off.** The two-tap capture flow is the reason
 *    anyone keeps this diary at all (Principle VI), and a required rating would slow down every
 *    entry to serve a feature most entries will not use (I6-01, I6-07).
 *  - **It is one row of five per feeling, not a slider.** Five stops is what the trajectory signal
 *    needs and what a person can answer without deliberating. A 1–100 scale is Daylio's model, and
 *    it buys precision the answer does not have (I6-08).
 *  - **The stops come from the backend.** `min` and `max` are served with the insights payload, so
 *    this client renders the scale rather than defining it (C-01).
 *  - **Every chosen feeling gets its own row.** This used to rate "the primary feeling" — the first
 *    word picked — which meant an entry that was *grateful and anxious* could say how strongly it
 *    was grateful and had no way to say anything at all about the anxious half. "How strongly" is a
 *    question about one feeling, so it is asked once per feeling, and the answers travel keyed by
 *    feeling so removing a word takes its rating with it.
 */

interface Props {
  /** The feelings on the entry, in order. An empty list renders nothing. */
  feelings: Feeling[];
  /** Ratings keyed by feeling key. A feeling absent from the map is unrated. */
  values: Record<string, number>;
  onChange: (values: Record<string, number>) => void;
  min: number;
  max: number;
}

export function IntensityDials({ feelings, values, onChange, min, max }: Props) {
  const groupId = useId();
  if (feelings.length === 0) return null;

  const stops = Array.from({ length: max - min + 1 }, (_, index) => min + index);

  function set(key: string, value: number | null) {
    const next = { ...values };
    if (value === null) delete next[key];
    else next[key] = value;
    onChange(next);
  }

  return (
    <fieldset className="intensity" aria-describedby={`${groupId}-hint`}>
      <legend className="intensity__legend">
        {feelings.length === 1 ? 'How strongly?' : 'How strongly did you feel each?'}
        <span className="intensity__optional"> optional</span>
      </legend>

      {feelings.map((feeling) => {
        const value = values[feeling.key] ?? null;
        return (
          <div className="intensity__feeling-row" key={feeling.key}>
            <p className="intensity__feeling">{feeling.label}</p>
            <div className="intensity__row">
              {stops.map((stop) => (
                <button
                  key={stop}
                  type="button"
                  className={`intensity__stop ${value !== null && stop <= value ? 'intensity__stop--on' : ''}`}
                  // Tapping the current value clears it: the way out of an optional field has to be
                  // as cheap as the way in, or "optional" only holds until the first tap.
                  onClick={() => set(feeling.key, value === stop ? null : stop)}
                  aria-pressed={value === stop}
                  // Named per feeling, because there is now more than one of these rows on screen
                  // and "3 of 5" alone would not say which word it rates.
                  aria-label={`${feeling.label}, ${stop} of ${max}`}
                >
                  <span className="tnum">{stop}</span>
                </button>
              ))}
              {value !== null && (
                <button
                  type="button"
                  className="btn btn--ghost btn--small intensity__clear"
                  onClick={() => set(feeling.key, null)}
                >
                  <Icon name="close" size="0.9em" />
                  Clear
                </button>
              )}
            </div>
          </div>
        );
      })}

      <p className="muted intensity__hint" id={`${groupId}-hint`}>
        Skip any of these and nothing changes — patterns never depend on them.
      </p>
    </fieldset>
  );
}
