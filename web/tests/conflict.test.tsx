/**
 * FR-023 / SC-008: when a change is rejected as out of date, the user's writing must survive.
 *
 * This is the failure path that actually gets hit, because FR-019 made staleness a permanent
 * condition rather than a brief race — a tab left open all afternoon is a stale view. The rule the
 * spec settles on is "reject and preserve": show what they wrote beside what's stored, and let them
 * decide. Never auto-merge, never silently pick a winner.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { ConflictView } from '../src/screens/ConflictScreen';
import type { Entry } from '../src/domain/types';

const stored: Entry = {
  id: 'e1',
  created_at: '2026-07-28T09:00:00',
  entry_date: '2026-07-28',
  mode: 'freeform',
  raw_text: 'Saved from the phone.',
  feeling_key: 'happy',
  feeling_keys: ['happy'],
  feeling_source: 'confirmed',
  feeling_intensity: null,
  feeling_intensities: {},
  guided_answers: [],
  suggested_feeling: null,
  suggested_feelings: [],
  version: 4,
};

const MINE = 'What I typed in the browser.';

function setup(overrides: Partial<Parameters<typeof ConflictView>[0]> = {}) {
  const onRetry = vi.fn();
  const onDiscard = vi.fn();
  const onCarryAcross = vi.fn();
  render(
    <ConflictView
      mine={MINE}
      current={stored}
      onRetry={onRetry}
      onDiscard={onDiscard}
      onCarryAcross={onCarryAcross}
      {...overrides}
    />,
  );
  return { onRetry, onDiscard, onCarryAcross };
}

describe('conflict resolution', () => {
  it('keeps the text the user wrote visible — nothing they typed is lost', () => {
    setup();

    expect(screen.getByText(MINE)).toBeInTheDocument();
  });

  it('shows the stored version alongside it', () => {
    setup();

    expect(screen.getByText(stored.raw_text)).toBeInTheDocument();
  });

  it('explains that the view was out of date', () => {
    setup();

    expect(screen.getByRole('alert')).toHaveTextContent(/changed|out of date/i);
  });

  it('offers all three resolutions', () => {
    setup();

    expect(screen.getByRole('button', { name: /keep mine/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /discard mine/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /copy mine/i })).toBeInTheDocument();
  });

  it('retries against the current version, not the stale one', async () => {
    const { onRetry } = setup();

    await userEvent.click(screen.getByRole('button', { name: /keep mine/i }));

    expect(onRetry).toHaveBeenCalledWith(MINE, stored.version);
  });

  it('discards only when the user explicitly says so', async () => {
    const { onDiscard, onRetry } = setup();

    await userEvent.click(screen.getByRole('button', { name: /discard mine/i }));

    expect(onDiscard).toHaveBeenCalledTimes(1);
    expect(onRetry).not.toHaveBeenCalled();
  });

  it('can carry the text back into the editor for manual merging', async () => {
    const { onCarryAcross } = setup();

    await userEvent.click(screen.getByRole('button', { name: /copy mine/i }));

    expect(onCarryAcross).toHaveBeenCalledWith(MINE);
  });

  it('never merges the two versions automatically', () => {
    setup();

    // A merged string would contain both halves in one node; they must stay separate.
    expect(screen.queryByText(`${MINE}${stored.raw_text}`)).not.toBeInTheDocument();
    expect(screen.queryByText(`${MINE} ${stored.raw_text}`)).not.toBeInTheDocument();
  });

  it('handles the deleted-elsewhere case without offering a retry', () => {
    setup({ current: null });

    expect(screen.getByRole('alert')).toHaveTextContent(/deleted|no longer exists/i);
    expect(screen.queryByRole('button', { name: /keep mine/i })).not.toBeInTheDocument();
    // The user's writing is still on screen even though there is nothing to save it back to.
    expect(screen.getByText(MINE)).toBeInTheDocument();
  });
});
