/**
 * FR-026 / SC-013: unsaved writing is never lost without the user confirming it — and equally, no
 * prompt may appear when there is nothing unsaved (a prompt with nothing to lose is itself a
 * defect, and Principle VI treats needless friction as a bug).
 *
 * This matters more on the web than it would on Android: FR-025 forbids storing drafts locally, so
 * this warning is the *only* protection in-progress writing has.
 */

import { act, fireEvent, renderHook } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useUnsavedGuard } from '../src/hooks/useUnsavedGuard';

function fireBeforeUnload(): boolean {
  const event = new Event('beforeunload', { cancelable: true });
  window.dispatchEvent(event);
  return event.defaultPrevented;
}

describe('useUnsavedGuard', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('does not intercept a close when there is nothing unsaved', () => {
    renderHook(() => useUnsavedGuard(false));

    expect(fireBeforeUnload()).toBe(false);
  });

  it('intercepts a close while there is unsaved text', () => {
    renderHook(() => useUnsavedGuard(true));

    expect(fireBeforeUnload()).toBe(true);
  });

  it('arms when the entry becomes dirty', () => {
    const { rerender } = renderHook(({ dirty }) => useUnsavedGuard(dirty), {
      initialProps: { dirty: false },
    });
    expect(fireBeforeUnload()).toBe(false);

    rerender({ dirty: true });

    expect(fireBeforeUnload()).toBe(true);
  });

  it('disarms once the entry is saved', () => {
    const { rerender } = renderHook(({ dirty }) => useUnsavedGuard(dirty), {
      initialProps: { dirty: true },
    });
    expect(fireBeforeUnload()).toBe(true);

    rerender({ dirty: false });

    expect(fireBeforeUnload()).toBe(false);
  });

  it('stops intercepting once unmounted', () => {
    const { unmount } = renderHook(() => useUnsavedGuard(true));

    act(() => unmount());

    expect(fireBeforeUnload()).toBe(false);
  });

  it('does not leave a stale listener behind when toggled repeatedly', () => {
    const addSpy = vi.spyOn(window, 'addEventListener');
    const removeSpy = vi.spyOn(window, 'removeEventListener');

    const { rerender, unmount } = renderHook(({ dirty }) => useUnsavedGuard(dirty), {
      initialProps: { dirty: true },
    });
    rerender({ dirty: false });
    rerender({ dirty: true });
    unmount();

    const added = addSpy.mock.calls.filter(([type]) => type === 'beforeunload').length;
    const removed = removeSpy.mock.calls.filter(([type]) => type === 'beforeunload').length;
    expect(added).toBe(removed);
  });

  it('blocks in-app link navigation when the user keeps their draft', () => {
    vi.spyOn(window, 'confirm').mockReturnValue(false);
    renderHook(() => useUnsavedGuard(true));
    const link = document.createElement('a');
    link.href = '/app/insights';
    document.body.append(link);

    const allowed = fireEvent.click(link);

    expect(allowed).toBe(false);
    expect(window.confirm).toHaveBeenCalledOnce();
    link.remove();
  });

  it('exposes the same confirmation for buttons that navigate programmatically', () => {
    vi.spyOn(window, 'confirm').mockReturnValue(false);
    const { result } = renderHook(() => useUnsavedGuard(true));

    expect(result.current.confirmDiscard()).toBe(false);
    expect(window.confirm).toHaveBeenCalledOnce();
  });
});
