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
 * backend.
 *
 * Each chip is marked with its feeling's colour rather than an emoji. Emoji were the obvious first
 * choice and the wrong one: they are a different drawing on every platform, they cannot be tinted
 * to match the calendar dots that mean the same thing, and "🥱 Exhausted" beside "😴 Sleepy" is a
 * distinction the user has to squint at. A colour that matches the calendar and the entry rail is
 * one the user learns once. Colour is never the only channel — the label is always present.
 */
export function FeelingChips({ feelings, selected, onSelect, suggestedKey, legend }: Props) {
  return (
    <fieldset className="feeling-chips">
      <legend>{legend}</legend>
      <div className="chip-grid">
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
              <span className="feeling-dot" aria-hidden="true" />
              <span>{feeling.label}</span>
              {isSuggested && <span className="chip__hint">suggested</span>}
            </label>
          );
        })}
      </div>
    </fieldset>
  );
}
