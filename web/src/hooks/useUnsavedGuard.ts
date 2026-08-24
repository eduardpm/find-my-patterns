import { useCallback, useEffect } from 'react';

const DISCARD_MESSAGE = 'You have unsaved writing. Leave this page and discard it?';

export interface UnsavedGuard {
  /** Use before programmatic in-app navigation, which does not fire `beforeunload`. */
  confirmDiscard: () => boolean;
}

/**
 * Warns before the tab closes while an entry has unsaved text (FR-026).
 *
 * This is the *only* protection in-progress writing has: FR-025 forbids storing drafts in the
 * browser, so there is nothing to recover from afterwards. The listener is registered only while
 * `dirty` is true — FR-026 explicitly forbids prompting when there is nothing unsaved.
 *
 * Known limitation, accepted in the spec's Edge Cases: `beforeunload` doesn't fire on a browser or
 * OS crash, so crash-time writing is genuinely lost.
 */
export function useUnsavedGuard(dirty: boolean): UnsavedGuard {
  const confirmDiscard = useCallback(() => !dirty || window.confirm(DISCARD_MESSAGE), [dirty]);

  useEffect(() => {
    if (!dirty) return;

    const handler = (event: BeforeUnloadEvent) => {
      // Browsers ignore custom text and show their own wording; preventDefault is what actually
      // triggers the prompt. The requirement is that the user is *asked*, not that we word it.
      event.preventDefault();
      event.returnValue = '';
    };

    window.addEventListener('beforeunload', handler);
    // React Router links do not unload the document. Intercept same-tab links at the document edge
    // so the app nav, entry cards, and any future internal links receive the same protection.
    const handleLink = (event: MouseEvent) => {
      if (
        event.defaultPrevented ||
        event.button !== 0 ||
        event.metaKey ||
        event.ctrlKey ||
        event.shiftKey ||
        event.altKey
      ) {
        return;
      }
      const target = event.target;
      const anchor =
        target instanceof Element ? target.closest<HTMLAnchorElement>('a[href]') : null;
      if (!anchor || anchor.target === '_blank' || anchor.hasAttribute('download')) return;
      const destination = new URL(anchor.href, window.location.href);
      if (
        destination.origin !== window.location.origin ||
        destination.href === window.location.href
      ) {
        return;
      }
      if (!window.confirm(DISCARD_MESSAGE)) {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
    };

    document.addEventListener('click', handleLink, true);
    return () => {
      window.removeEventListener('beforeunload', handler);
      document.removeEventListener('click', handleLink, true);
    };
  }, [dirty]);

  return { confirmDiscard };
}
