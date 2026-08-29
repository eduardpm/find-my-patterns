import { useEffect, useId, useRef, useState } from 'react';
import type { Feeling, FeelingGroup, FeelingVocabulary } from '../domain/types';
import { Icon } from './Icon';

interface Props {
  vocabulary: FeelingVocabulary | null;
  /** Every feeling currently on the entry, in the order they were chosen. */
  selected: string[];
  onChange: (keys: string[]) => void;
  /** Set when the backend proposed these, so the UI can show what it suggested (FR-005). */
  suggestedKeys?: string[];
  /** How many feelings one entry may carry. The backend rejects more; this stops it happening. */
  max?: number;
  legend: string;
}

/**
 * Feeling selection, two levels deep.
 *
 * The vocabulary is around thirty words in four groups, which is far more than fits on one screen
 * without turning the fastest step of writing an entry into a scanning exercise (Principle VI). So
 * the first level is the only thing always on screen: four group buttons, each of which opens that
 * group's own words. Choosing "Tense" and then "Overwhelmed" is two taps for a precision the old
 * flat row of eight could not express at all.
 *
 * Three deliberate choices:
 *
 *  - **A real `<dialog>`, opened with `showModal()`.** Focus trapping, Escape-to-close, the
 *    backdrop, and making the rest of the page inert are all things the element does correctly and
 *    a div would have to reimplement — badly, in the usual case. It is the same reasoning that
 *    made the calendar a real `<table>`.
 *  - **Checkboxes inside, not radios.** An entry can carry several feelings, so the control is
 *    genuinely multi-select and must announce itself as one.
 *  - **Colour by group, never by individual feeling.** Thirty distinguishable hues do not exist;
 *    four do. Every feeling in a group shares that group's valence, so one accent per group is
 *    honest. Colour is never the only channel — the chosen feelings are always spelled out.
 */
export function FeelingChips({
  vocabulary,
  selected,
  onChange,
  suggestedKeys = [],
  max = 4,
  legend,
}: Props) {
  const [openGroup, setOpenGroup] = useState<FeelingGroup | null>(null);
  const groups = vocabulary?.groups ?? [];
  const byKey = new Map((vocabulary?.feelings ?? []).map((feeling) => [feeling.key, feeling]));
  const chosen = selected.flatMap((key) => byKey.get(key) ?? []);
  const suggested = new Set(suggestedKeys);
  const groupId = useId();

  function toggle(key: string) {
    if (selected.includes(key)) {
      onChange(selected.filter((existing) => existing !== key));
      return;
    }
    if (selected.length >= max) return;
    onChange([...selected, key]);
  }

  return (
    <section className="feeling-picker" aria-labelledby={`${groupId}-legend`}>
      <h2 id={`${groupId}-legend`} className="feeling-picker__legend">
        {legend}
      </h2>

      {/*
        The chosen feelings sit above the groups, not inside them: after a group's dialog closes
        this row is the only place the answer is visible, and a user scanning back up the page
        should not have to reopen four dialogs to remember what they picked. Each is removable in
        place, which is the whole reason it is a button and not a label.
      */}
      {chosen.length > 0 ? (
        <ul className="feeling-picker__chosen" aria-label="Chosen feelings">
          {chosen.map((feeling) => (
            <li key={feeling.key}>
              <button
                type="button"
                className="chip chip--chosen"
                data-feeling-group={feeling.group_key}
                // The visible content reads as a label; the control's job is removal, so the
                // accessible name says so outright rather than leaving a screen-reader user to
                // infer it from an icon.
                aria-label={
                  suggested.has(feeling.key)
                    ? `Remove ${feeling.label}, suggested`
                    : `Remove ${feeling.label}`
                }
                onClick={() => toggle(feeling.key)}
              >
                <span className="feeling-dot" aria-hidden="true" />
                <span>{feeling.label}</span>
                {suggested.has(feeling.key) && <span className="chip__hint">suggested</span>}
                <Icon name="close" />
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p className="feeling-picker__empty muted">
          Nothing chosen yet — pick a group to see the feelings inside it.
        </p>
      )}

      <ul className="feeling-picker__groups">
        {groups.map((group) => {
          const countInGroup = group.feelings.filter((feeling) =>
            selected.includes(feeling.key),
          ).length;
          return (
            <li key={group.key}>
              <button
                type="button"
                className={`chip chip--group${countInGroup > 0 ? ' chip--selected' : ''}`}
                data-feeling-group={group.key}
                aria-haspopup="dialog"
                // The badge is a bare numeral, which would be read as part of the group's name.
                // Naming the button outright says what the number means.
                aria-label={
                  countInGroup > 0 ? `${group.label}, ${countInGroup} chosen` : group.label
                }
                onClick={() => setOpenGroup(group)}
              >
                <span className="feeling-dot" aria-hidden="true" />
                <span>{group.label}</span>
                {countInGroup > 0 && (
                  <span className="chip__count tnum" aria-hidden="true">
                    {countInGroup}
                  </span>
                )}
              </button>
            </li>
          );
        })}
      </ul>

      {/*
        A hint rather than a disabled-looking row: hiding the remaining groups at the limit would
        make the control look broken, and the chips the user could still *remove* are right above.
      */}
      {selected.length >= max && (
        <p className="feeling-picker__limit muted" role="status">
          That is as many as one entry can carry. Remove one to choose another.
        </p>
      )}

      {openGroup && (
        <GroupDialog
          group={openGroup}
          selected={selected}
          suggested={suggested}
          atLimit={selected.length >= max}
          onToggle={toggle}
          onClose={() => setOpenGroup(null)}
        />
      )}
    </section>
  );
}

interface DialogProps {
  group: FeelingGroup;
  selected: string[];
  suggested: Set<string>;
  atLimit: boolean;
  onToggle: (key: string) => void;
  onClose: () => void;
}

function GroupDialog({ group, selected, suggested, atLimit, onToggle, onClose }: DialogProps) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();

  // `showModal()` rather than the `open` attribute: only the method makes the dialog modal, and
  // modality is the entire point — it is what traps focus and makes the page behind it inert.
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog || dialog.open) return;
    dialog.showModal();
  }, []);

  return (
    <dialog
      ref={ref}
      className="feeling-dialog"
      aria-labelledby={titleId}
      data-feeling-group={group.key}
      // Fires for Escape and for the close button alike, so there is one way out of this component
      // rather than two that can disagree.
      onClose={onClose}
      // Clicking the backdrop lands on the dialog element itself; clicking any content lands on a
      // child. That difference is the whole test — no invisible overlay div is needed.
      onClick={(event) => {
        if (event.target === ref.current) ref.current?.close();
      }}
    >
      <div className="feeling-dialog__head">
        <h2 id={titleId}>{group.label}</h2>
        <button
          type="button"
          className="btn btn--icon"
          onClick={() => ref.current?.close()}
          aria-label={`Close ${group.label}`}
        >
          <Icon name="close" />
        </button>
      </div>

      <p className="feeling-dialog__hint muted">
        Choose as many as fit. Tap one again to remove it.
      </p>

      <div className="chip-grid">
        {group.feelings.map((feeling: Feeling) => {
          const isSelected = selected.includes(feeling.key);
          return (
            <label
              key={feeling.key}
              className={`chip${isSelected ? ' chip--selected' : ''}`}
              data-feeling-group={feeling.group_key}
            >
              <input
                type="checkbox"
                checked={isSelected}
                // Only unselected chips are disabled at the limit: the user must always be able to
                // undo their way back under it from inside the dialog they are standing in.
                disabled={!isSelected && atLimit}
                onChange={() => onToggle(feeling.key)}
                className="visually-hidden"
              />
              <span className="feeling-dot" aria-hidden="true" />
              <span>{feeling.label}</span>
              {suggested.has(feeling.key) && <span className="chip__hint">suggested</span>}
            </label>
          );
        })}
      </div>

      <div className="feeling-dialog__actions">
        <button type="button" className="btn" onClick={() => ref.current?.close()}>
          Done
          <Icon name="check" />
        </button>
      </div>
    </dialog>
  );
}
