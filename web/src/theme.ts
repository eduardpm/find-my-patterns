/**
 * Appearance: which paper the diary is written on, and whether it is lit or dark.
 *
 * Two independent choices, stored together. The *palette* picks one of the three token sets in
 * `styles/tokens.css`; the *mode* picks that palette's light or dark half, or defers to the
 * operating system. Both are written onto <html> as `data-palette` / `data-mode`, which is the
 * whole mechanism -- every colour in the app already comes from a token, so nothing else has to
 * know a theme exists.
 *
 * The mode attribute is always a literal `light` or `dark`, never `system`: resolving the system
 * preference here rather than with a `prefers-color-scheme` media query in CSS means each palette
 * needs one dark block instead of two, and it lets the settings screen show what "System" is
 * currently resolving to. The cost is that a listener has to keep it in sync when the OS flips,
 * which [startAppearanceSync] does.
 *
 * localStorage is used deliberately and narrowly. FR-025 forbids diary content in storage that
 * outlives the tab, and that rule is not bent here: what is stored is two enum values naming a
 * palette and a mode. Nothing about them says anything about what was written or felt, which is
 * also why they never go near the backend -- the server has no reason to learn which paper this
 * device prefers.
 */

export type PaletteId = 'paper' | 'sage' | 'dusk';
export type ModePreference = 'system' | 'light' | 'dark';
export type ResolvedMode = 'light' | 'dark';

export interface Appearance {
  palette: PaletteId;
  mode: ModePreference;
}

export interface PaletteMeta {
  id: PaletteId;
  /** Shown as the option's title. */
  label: string;
  /** One line, in the product's voice: what it is, not what it does. */
  description: string;
}

/**
 * The three papers, in the order they are offered.
 *
 * `paper` is first because it is the default and the one the product was designed around; the
 * other two are alternatives at the same level, not upgrades.
 */
export const PALETTES: readonly PaletteMeta[] = [
  {
    id: 'paper',
    label: 'Warm paper',
    description: 'Cream and journal brown, with ink violet for anything the diary is guessing at.',
  },
  {
    id: 'sage',
    label: 'Sage',
    description: 'A greener page and a pine ink. The quietest of the three.',
  },
  {
    id: 'dusk',
    label: 'Dusk',
    description: 'Cool grey-blue and deep indigo, for writing late with the lights still on.',
  },
];

export const MODES: readonly { id: ModePreference; label: string }[] = [
  { id: 'system', label: 'System' },
  { id: 'light', label: 'Light' },
  { id: 'dark', label: 'Dark' },
];

const STORAGE_KEY = 'mood-diary:appearance';

export const DEFAULT_APPEARANCE: Appearance = { palette: 'paper', mode: 'system' };

const isPaletteId = (value: unknown): value is PaletteId =>
  PALETTES.some((palette) => palette.id === value);

const isModePreference = (value: unknown): value is ModePreference =>
  MODES.some((mode) => mode.id === value);

/**
 * Reads the stored choice, falling back to the default for anything unrecognised.
 *
 * Storage can throw outright (Safari with cookies blocked, a locked-down private window), and it
 * can also hold a palette id from a build that offered a palette this one does not. Both end at
 * the same place: the warm paper the app has always opened with.
 */
export function readAppearance(): Appearance {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_APPEARANCE;
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== 'object' || parsed === null) return DEFAULT_APPEARANCE;
    const { palette, mode } = parsed as Partial<Appearance>;
    return {
      palette: isPaletteId(palette) ? palette : DEFAULT_APPEARANCE.palette,
      mode: isModePreference(mode) ? mode : DEFAULT_APPEARANCE.mode,
    };
  } catch {
    return DEFAULT_APPEARANCE;
  }
}

/** Persists the choice. A failure here loses the preference on reload but never the app. */
export function writeAppearance(appearance: Appearance): void {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(appearance));
  } catch {
    /* private mode, blocked storage: the choice still applies for this session. */
  }
}

/** What the operating system is currently asking for. */
export function systemMode(): ResolvedMode {
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function resolveMode(mode: ModePreference): ResolvedMode {
  return mode === 'system' ? systemMode() : mode;
}

/**
 * Writes the pair onto <html>. Everything visual follows from these two attributes.
 *
 * The switch is deliberately abrupt. Several controls transition their background so that hover
 * and press feel alive, and those same transitions turn a theme change into a couple of hundred
 * milliseconds of dark text crawling across a lightening card — text colour is not animated, so
 * for that moment the two are mismatched and some labels are unreadable. Suppressing transitions
 * for one frame makes the whole page change at once, which is both legible and closer to what
 * flipping a light switch does.
 */
export function applyAppearance(appearance: Appearance): void {
  const root = document.documentElement;
  root.dataset.themeSwitching = '';
  root.dataset.palette = appearance.palette;
  root.dataset.mode = resolveMode(appearance.mode);
  // Two frames: one for the new values to be painted, one to hand the transitions back.
  requestAnimationFrame(() => {
    requestAnimationFrame(() => delete root.dataset.themeSwitching);
  });
}

/**
 * Keeps `data-mode` truthful while the app is open.
 *
 * Only matters while the preference is "System": the OS can flip at sunset, or because the user
 * changed it in another window, and the resolved attribute would otherwise stay at whatever it was
 * when the tab loaded. Returns its own unsubscribe.
 */
export function startAppearanceSync(getAppearance: () => Appearance): () => void {
  const query = window.matchMedia?.('(prefers-color-scheme: dark)');
  if (!query) return () => undefined;
  const onChange = () => {
    const appearance = getAppearance();
    if (appearance.mode === 'system') applyAppearance(appearance);
  };
  query.addEventListener('change', onChange);
  return () => query.removeEventListener('change', onChange);
}
