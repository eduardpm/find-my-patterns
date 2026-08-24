import type { Feeling } from '../domain/types';

interface Props {
  feelings: Feeling[];
  selected: string | null;
  onSelect: (key: string) => void;
  /** Set when the backend suggested this feeling, so the UI can show what it proposed (FR-005). */
  suggestedKey?: string | null;
  legend: string;
}

/**
 * Feeling selection as a real radio group.
 *
 * A radio group rather than a row of buttons because it is genuinely a single-choice control:
 * that gives arrow-key navigation, a single tab stop, and correct announcement for free — which is
 * what FR-014's keyboard-only requirement and FR-027's labelling bar actually need.
 *
 * The list is passed in, never hardcoded: constitution Principle VII keeps the feeling set in the
 * backend. Emoji live here because presentation is explicitly the client's business.
 */

const EMOJI: Record<string, string> = {
  happy: '😊',
  excited: '🤩',
  neutral: '😐',
  sleepy: '😴',
  exhausted: '🥱',
  stressed: '😖',
  sad: '😢',
  depressed: '😞',
};

export function FeelingChips({ feelings, selected, onSelect, suggestedKey, legend }: Props) {
  return (
    <fieldset className="feeling-chips">
      <legend>{legend}</legend>
      <div className="row">
        {feelings.map((feeling) => {
          const isSuggested = suggestedKey === feeling.key;
          return (
            <label
              key={feeling.key}
              className={`chip${selected === feeling.key ? ' chip--selected' : ''}`}
              data-feeling={feeling.key}
            >
              <input
                type="radio"
                name="feeling"
                value={feeling.key}
                checked={selected === feeling.key}
                onChange={() => onSelect(feeling.key)}
                className="visually-hidden"
              />
              <span aria-hidden="true">{EMOJI[feeling.key] ?? '•'}</span>
              <span>{feeling.label}</span>
              {isSuggested && <span className="chip__hint"> (suggested)</span>}
            </label>
          );
        })}
      </div>
    </fieldset>
  );
}
