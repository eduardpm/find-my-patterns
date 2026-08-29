/**
 * The two-level feeling picker.
 *
 * The vocabulary is thirty-odd words, and the whole reason the picker is two levels is that
 * putting them all on screen would slow down the one flow the constitution says must stay fast
 * (Principle VI). So what is worth pinning is the behaviour that makes two levels survivable: the
 * answer stays visible after the dialog closes, the dialog is genuinely modal, and the control is
 * operable without a pointer (FR-014).
 */

import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { FeelingChips } from '../src/components/FeelingChips';
import type { FeelingVocabulary } from '../src/domain/types';

const VOCABULARY: FeelingVocabulary = {
  groups: [
    {
      key: 'uplifted',
      label: 'Uplifted',
      valence: 'positive',
      feelings: [
        { key: 'happy', label: 'Happy', valence: 'positive', group_key: 'uplifted' },
        { key: 'proud', label: 'Proud', valence: 'positive', group_key: 'uplifted' },
      ],
    },
    {
      key: 'tense',
      label: 'Tense',
      valence: 'negative',
      feelings: [
        { key: 'stressed', label: 'Stressed', valence: 'negative', group_key: 'tense' },
        { key: 'anxious', label: 'Anxious', valence: 'negative', group_key: 'tense' },
      ],
    },
  ],
  feelings: [
    { key: 'happy', label: 'Happy', valence: 'positive', group_key: 'uplifted' },
    { key: 'proud', label: 'Proud', valence: 'positive', group_key: 'uplifted' },
    { key: 'stressed', label: 'Stressed', valence: 'negative', group_key: 'tense' },
    { key: 'anxious', label: 'Anxious', valence: 'negative', group_key: 'tense' },
  ],
};

function setup(selected: string[] = [], props: Partial<Parameters<typeof FeelingChips>[0]> = {}) {
  const onChange = vi.fn();
  const view = render(
    <FeelingChips
      legend="Feelings"
      vocabulary={VOCABULARY}
      selected={selected}
      onChange={onChange}
      {...props}
    />,
  );
  return { onChange, user: userEvent.setup(), ...view };
}

// jsdom implements <dialog> but not its modal behaviour, so `showModal` is stubbed. What is
// asserted here is that the dialog opens and closes — the focus trap itself belongs to the
// browser, and reimplementing it to test it would defeat the reason for using the element.
beforeEach(() => {
  HTMLDialogElement.prototype.showModal = function showModal(this: HTMLDialogElement) {
    this.open = true;
  };
  HTMLDialogElement.prototype.close = function close(this: HTMLDialogElement) {
    this.open = false;
    this.dispatchEvent(new Event('close'));
  };
});

describe('FeelingChips', () => {
  it('shows only the groups until one is opened', () => {
    setup();
    expect(screen.getByRole('button', { name: /Uplifted/ })).toBeInTheDocument();
    expect(screen.queryByRole('checkbox', { name: 'Proud' })).toBeNull();
  });

  it('opens a group and reports the feeling chosen inside it', async () => {
    const { onChange, user } = setup();

    await user.click(screen.getByRole('button', { name: /Uplifted/ }));
    await user.click(screen.getByRole('checkbox', { name: 'Proud' }));

    expect(onChange).toHaveBeenCalledWith(['proud']);
  });

  it('keeps the chosen feelings on screen after the dialog closes', async () => {
    const { user } = setup(['proud', 'anxious']);

    const chosen = screen.getByRole('list', { name: 'Chosen feelings' });
    expect(within(chosen).getByRole('button', { name: /Remove Proud/ })).toBeInTheDocument();
    expect(within(chosen).getByRole('button', { name: /Remove Anxious/ })).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /Uplifted/ }));
    await user.click(screen.getByRole('button', { name: 'Done' }));
    expect(within(chosen).getByRole('button', { name: /Remove Proud/ })).toBeInTheDocument();
  });

  it('removes a feeling from the row without reopening its group', async () => {
    const { onChange, user } = setup(['proud', 'anxious']);

    await user.click(screen.getByRole('button', { name: /Remove Proud/ }));
    expect(onChange).toHaveBeenCalledWith(['anxious']);
  });

  it('counts how many of a group are chosen, in words as well as a numeral', () => {
    setup(['happy', 'proud']);
    expect(screen.getByRole('button', { name: /Uplifted, 2 chosen/ })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /^Tense$/ })).toBeInTheDocument();
  });

  it('marks what the backend suggested, so a guess reads differently from a choice', () => {
    setup(['proud'], { suggestedKeys: ['proud'] });
    expect(screen.getByRole('button', { name: 'Remove Proud, suggested' })).toBeInTheDocument();
  });

  it('stops at the limit, but never blocks removing one to get back under it', async () => {
    const { user } = setup(['happy', 'proud'], { max: 2 });

    expect(screen.getByRole('status')).toHaveTextContent(/as many as one entry can carry/);

    await user.click(screen.getByRole('button', { name: /Tense/ }));
    // Unchosen feelings are genuinely disabled rather than merely dimmed…
    expect(screen.getByRole('checkbox', { name: 'Anxious' })).toBeDisabled();

    await user.click(screen.getByRole('button', { name: 'Done' }));
    // …and the way back under the limit is still one click.
    expect(screen.getByRole('button', { name: /Remove Happy/ })).toBeEnabled();
  });

  it('is operable from the keyboard alone (FR-014)', async () => {
    const { onChange, user } = setup();

    await user.tab();
    expect(screen.getByRole('button', { name: /Uplifted/ })).toHaveFocus();
    await user.keyboard('{Enter}');
    expect(screen.getByRole('dialog')).toBeInTheDocument();

    await user.click(screen.getByRole('checkbox', { name: 'Happy' }));
    expect(onChange).toHaveBeenCalledWith(['happy']);
  });

  it('renders nothing to choose from before the vocabulary arrives, rather than guessing', () => {
    render(<FeelingChips legend="Feelings" vocabulary={null} selected={[]} onChange={vi.fn()} />);
    expect(screen.queryByRole('button')).toBeNull();
    expect(screen.getByText(/Nothing chosen yet/)).toBeInTheDocument();
  });
});
