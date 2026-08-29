import { useCallback, useSyncExternalStore } from 'react';
import {
  type Appearance,
  type PaletteId,
  type ModePreference,
  type ResolvedMode,
  applyAppearance,
  readAppearance,
  resolveMode,
  startAppearanceSync,
  writeAppearance,
} from '../theme';

/**
 * The current appearance, as a module-level store rather than React state.
 *
 * It is read in two places that are nowhere near each other in the tree — the shell, which starts
 * the system-preference listener, and the settings screen, which changes it — and the value is a
 * pair of enums that already lives on <html> anyway. A context provider around the whole app to
 * carry two strings would be more moving parts than the thing it carries.
 *
 * `useSyncExternalStore` rather than a hand-rolled `useState` + effect: the source of truth is
 * outside React (the DOM attributes and localStorage), and this is the hook that exists for
 * exactly that, without tearing under concurrent rendering.
 */

let current: Appearance = readAppearance();
const listeners = new Set<() => void>();

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

const getSnapshot = (): Appearance => current;

function set(next: Appearance): void {
  current = next;
  writeAppearance(next);
  applyAppearance(next);
  listeners.forEach((listener) => listener());
}

/**
 * Applies the stored choice, and keeps it in step with the OS while "System" is selected.
 *
 * Called once from the app shell. The attributes are normally already correct — index.html sets
 * them before first paint so the page never flashes the wrong paper — but re-applying costs
 * nothing and covers the case where that inline script was skipped.
 */
export function initAppearance(): () => void {
  applyAppearance(current);
  return startAppearanceSync(getSnapshot);
}

export interface AppearanceControls {
  appearance: Appearance;
  /** `light` or `dark` — what "System" currently works out to, for labelling. */
  resolved: ResolvedMode;
  setPalette: (palette: PaletteId) => void;
  setMode: (mode: ModePreference) => void;
}

export function useAppearance(): AppearanceControls {
  const appearance = useSyncExternalStore(subscribe, getSnapshot, getSnapshot);

  const setPalette = useCallback((palette: PaletteId) => set({ ...current, palette }), []);
  const setMode = useCallback((mode: ModePreference) => set({ ...current, mode }), []);

  return { appearance, resolved: resolveMode(appearance.mode), setPalette, setMode };
}
