import type { SVGProps } from 'react';

/**
 * The app's icon set, inlined.
 *
 * Inline rather than an icon package because index.html rules out third-party requests (FR-017) and
 * a dependency would be a lot of bytes for eleven glyphs. Inline rather than emoji — which is what
 * this replaced — because emoji render as a different picture on every platform, cannot be tinted
 * by a design token, and land at unpredictable sizes next to text.
 *
 * Every glyph is drawn on a 24×24 grid with a 1.75 stroke and inherits `currentColor`, so an icon
 * always matches the text it sits beside. Sizing is in `em` for the same reason: an icon in a
 * label should shrink with the label.
 *
 * Accessibility: decorative by default (`aria-hidden`), because nearly every icon here sits next to
 * its own visible text. Pass a `title` only when the icon is genuinely the only label — that swaps
 * it to `role="img"` with an accessible name.
 */

const PATHS = {
  /** Brand mark: an open book. */
  book: 'M12 6.5C10.5 5.2 8.6 4.5 6.5 4.5H4a1 1 0 0 0-1 1v11a1 1 0 0 0 1 1h2.5c2.1 0 4 .7 5.5 2m0-13.5c1.5-1.3 3.4-2 5.5-2H20a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1h-2.5c-2.1 0-4 .7-5.5 2m0-13.5v13.5',
  plus: 'M12 5v14M5 12h14',
  refresh: 'M20 11a8 8 0 1 0-.6 4M20 5v6h-6',
  chevronLeft: 'M15 5l-7 7 7 7',
  chevronRight: 'M9 5l7 7-7 7',
  mic: 'M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3zM5 11a7 7 0 0 0 14 0M12 18v3',
  trash:
    'M4 7h16M9.5 7V5.5A1.5 1.5 0 0 1 11 4h2a1.5 1.5 0 0 1 1.5 1.5V7M6.5 7l.8 12.1a1.5 1.5 0 0 0 1.5 1.4h6.4a1.5 1.5 0 0 0 1.5-1.4L17.5 7',
  check: 'M4.5 12.5l5 5 10-11',
  close: 'M6 6l12 12M18 6L6 18',
  /** Insights: a pattern that is worth keeping — a rising line. */
  trendUp: 'M4 17l5.5-5.5 3.5 3.5L20 8M20 8h-4.5M20 8v4.5',
  /** …and one worth changing — a falling line. */
  trendDown: 'M4 7l5.5 5.5L13 9l7 7m0 0h-4.5M20 16v-4.5',
  spark: 'M12 3.5l1.9 5.1 5.1 1.9-5.1 1.9L12 17.5l-1.9-5.1L5 10.5l5.1-1.9z',
  warning: 'M12 4.5l8.5 15h-17zM12 10v4.5M12 17.2v.1',
  /** The evidence trail: a stack of entries the pattern rests on (A1). */
  layers: 'M12 3.5l9 5-9 5-9-5zM3 13l9 5 9-5M3 17l9 5 9-5',
  /** A pattern that has been withdrawn, or a historical one — time, not failure. */
  clock: 'M12 3.5a8.5 8.5 0 1 0 0 17 8.5 8.5 0 0 0 0-17zM12 7v5.2l3.4 2',
  /** The two-topic tangle a confounder warning is about (I2). */
  link: 'M10 13.5a4 4 0 0 0 5.7 0l2.8-2.8a4 4 0 0 0-5.7-5.7l-1.6 1.6M14 10.5a4 4 0 0 0-5.7 0l-2.8 2.8a4 4 0 1 0 5.7 5.7l1.6-1.6',
  /*
   * Settings, and the three appearance modes.
   *
   * Sliders rather than the usual cogwheel: a cog's teeth are the first thing to turn to mush at
   * the 16px this is actually drawn at, and two tracks with a handle each survive it. The mode
   * glyphs are the platform-conventional trio — a sun, a moon, and a screen for "whatever this
   * machine is doing" — because a segmented control of three words is where a person's eye stops.
   */
  settings:
    'M4 9h9M17 9h3M4 15h3M11 15h9M17 9a2 2 0 1 1-4 0 2 2 0 0 1 4 0M11 15a2 2 0 1 1-4 0 2 2 0 0 1 4 0',
  sun: 'M12 7.5a4.5 4.5 0 1 0 0 9 4.5 4.5 0 0 0 0-9zM12 2.6v1.9M12 19.5v1.9M2.6 12h1.9M19.5 12h1.9M5.3 5.3l1.3 1.3M17.4 17.4l1.3 1.3M18.7 5.3l-1.3 1.3M6.6 17.4l-1.3 1.3',
  moon: 'M20.2 14.6A8.6 8.6 0 0 1 9.4 3.8a8.6 8.6 0 1 0 10.8 10.8z',
  monitor:
    'M4 5.5h16a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1zM9 20.5h6M12 16.5v4',
} as const;

export type IconName = keyof typeof PATHS;

interface Props extends Omit<SVGProps<SVGSVGElement>, 'name'> {
  name: IconName;
  /** Width and height, in `em` so the icon tracks its neighbouring text. Defaults to 1.15em. */
  size?: string;
  /** Supply only when the icon is the sole label for its control. */
  title?: string;
}

export function Icon({ name, size = '1.15em', title, ...rest }: Props) {
  const labelled = title !== undefined;

  return (
    <svg
      className="icon"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      role={labelled ? 'img' : undefined}
      aria-hidden={labelled ? undefined : true}
      focusable="false"
      {...rest}
    >
      {labelled && <title>{title}</title>}
      <path d={PATHS[name]} />
    </svg>
  );
}
