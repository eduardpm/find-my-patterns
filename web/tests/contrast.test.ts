/**
 * Contrast audit for `--feeling-group-*` composites, across all six palette combinations (three
 * papers x light/dark). Written for #152, whose whole premise is that `tokens.css` drifted from
 * `mobile/lib/core/theme/journal_palette.dart` for months because nobody computed a number here --
 * the file's own comment claimed contrast was "checked against its intended surface" without a
 * test to back that claim up. `mobile/test/core/theme/contrast_test.dart` (#149) is the model this
 * follows: pairs are facts about real call sites, not an abstract sweep of the token file, and
 * ratios are computed with the true WCAG formula rather than eyeballed.
 *
 * Values are read out of the literal stylesheets (`tokens.css`, `base.css`) at test time rather
 * than hand-copied into constants here -- hand-copying is exactly the failure mode this file
 * exists to catch, and duplicating it inside the regression guard itself would defeat the point.
 * jsdom cannot compute `color-mix()` or resolve CSS custom properties from linked stylesheets, so
 * this file re-implements the (well-specified, easily verified) sRGB alpha-blend and WCAG
 * relative-luminance math directly rather than depending on a browser DOM.
 *
 * Three composites are checked, one per real call site that paints a `--feeling-group-*` value:
 *
 *  1. **The chip's own tinted fill vs. the colour drawn on top of it.** `.chip--selected` (base.css
 *     ~969-976) draws a 2px border in `--feeling-color` over `color-mix(in srgb, --feeling-color
 *     N%, transparent)` -- the same shape of composite that made two mobile pairs fail 4.5:1
 *     (#149). `.feeling-dot` (base.css ~552-563) paints the same full-strength colour over the same
 *     fill when it sits inside a selected chip. Both are graphical UI components, not text --
 *     `.chip--selected` explicitly keeps its *label* in `--color-on-surface` (base.css ~975), never
 *     in the feeling hue -- so the applicable WCAG 1.4.11 target is 3.0:1, not 4.5:1. This is the
 *     one #152 is actually about: it settles, with a number, whether web hits the same failure
 *     mode mobile did (it does not -- see the PR description for the measured ratios).
 *  2. **A feeling hue painted as text or a border on an opaque card.** `.entry-card__feeling` (base
 *     .css ~626-633) paints its label directly in `--feeling-color` on `.card`'s
 *     `--color-surface-container` background (base.css ~460); `.feeling-dialog`'s left border (base
 *     .css ~861) and an unselected chip's `.feeling-dot` land on the same pair of colours. This is
 *     real body text, so it is held to the full 4.5:1.
 *  3. **The near-white/near-black badge text on a fully-saturated feeling background.**
 *     `.chip--group .chip__count` (base.css ~820-828) is the one place a feeling colour is the
 *     *background* rather than the foreground: `--color-surface-container` is painted as text
 *     directly on `--feeling-color` at full strength. Held to 4.5:1 as text.
 */

import { describe, expect, it } from 'vitest';
// Vite's `?raw` suffix imports a file's literal text content as a string (declared by the
// `vite/client` types already in tsconfig.json's `types`). No Node built-ins needed, and no risk
// of hand-copying the values this file is meant to check against drift.
import tokensCss from '../src/styles/tokens.css?raw';
import baseCss from '../src/styles/base.css?raw';

// ---- Pull the fill percentage and the chip's text colour out of base.css itself, rather than
// hard-coding them, so a future edit to `.chip--selected` is caught structurally: if the rule
// stops matching this shape, the test fails loudly instead of silently checking a stale composite.
const chipSelectedBlock = baseCss.match(/\.chip--selected\s*\{([^}]*)\}/s)?.[1];
if (!chipSelectedBlock) {
  throw new Error('Could not find .chip--selected in base.css -- has the rule moved or renamed?');
}

const fillPercentMatch = chipSelectedBlock.match(
  /color-mix\(in srgb, var\(--feeling-color, var\(--color-primary\)\) (\d+)%, transparent\)/,
);
if (!fillPercentMatch) {
  throw new Error(
    '.chip--selected no longer fills with color-mix(--feeling-color N%, transparent) -- the ' +
      '12%-fill composite this file checks (#152) may no longer be what the component paints.',
  );
}
const CHIP_FILL_PERCENT = Number(fillPercentMatch[1]);

// `.chip--selected` must keep its label out of the feeling hue for pair 1's 3.0:1 (non-text)
// target to be the right target. If this ever changes to `var(--feeling-color, ...)`, the chip
// would start painting text on its own tinted fill exactly the way mobile's did before #149, and
// this composite would need the full 4.5:1 text target instead.
it('.chip--selected keeps its label text out of the feeling hue', () => {
  expect(chipSelectedBlock).toMatch(/color:\s*var\(--color-on-surface\)\s*;/);
});

// ---- Extract one palette/mode combination's tokens from tokens.css.
function extractBlock(selectorPattern: string): string {
  const re = new RegExp(`${selectorPattern}\\s*\\{([^}]*)\\}`, 's');
  const match = tokensCss.match(re);
  if (!match) {
    throw new Error(`Could not find a tokens.css block matching ${selectorPattern}`);
  }
  return match[1];
}

function property(block: string, name: string): string {
  const match = block.match(new RegExp(`--${name}:\\s*(#[0-9a-fA-F]{6})\\s*;`));
  if (!match) {
    throw new Error(`--${name} not found in tokens.css block`);
  }
  return match[1];
}

/** `[data-palette='paper']`-style attribute selector, as a regex-source string. */
function attr(name: string, value: string): string {
  return `\\[${name}='${value}'\\]`;
}

interface Combo {
  name: string;
  surface: string;
  surfaceContainer: string;
  feelings: Record<'uplifted' | 'steady' | 'tense' | 'low', string>;
}

function readCombo(name: string, selector: string): Combo {
  const block = extractBlock(selector);
  return {
    name,
    surface: property(block, 'color-surface'),
    surfaceContainer: property(block, 'color-surface-container'),
    feelings: {
      uplifted: property(block, 'feeling-group-uplifted'),
      steady: property(block, 'feeling-group-steady'),
      tense: property(block, 'feeling-group-tense'),
      low: property(block, 'feeling-group-low'),
    },
  };
}

const combos: Combo[] = [
  readCombo('paper/light', attr('data-palette', 'paper')),
  readCombo('sage/light', attr('data-palette', 'sage')),
  readCombo('dusk/light', attr('data-palette', 'dusk')),
  readCombo('paper/dark', attr('data-palette', 'paper') + attr('data-mode', 'dark')),
  readCombo('sage/dark', attr('data-palette', 'sage') + attr('data-mode', 'dark')),
  readCombo('dusk/dark', attr('data-palette', 'dusk') + attr('data-mode', 'dark')),
];

// ---- WCAG 2.x contrast math. Mirrors mobile/test/core/theme/contrast_test.dart's
// `_contrastRatio`/`_composited` exactly, so the two clients' regression guards agree on what
// "passes" means.

function hexToRgb(hex: string): [number, number, number] {
  const clean = hex.replace('#', '');
  return [
    parseInt(clean.slice(0, 2), 16),
    parseInt(clean.slice(2, 4), 16),
    parseInt(clean.slice(4, 6), 16),
  ];
}

function srgbChannelToLinear(channel: number): number {
  const scaled = channel / 255;
  return scaled <= 0.03928 ? scaled / 12.92 : ((scaled + 0.055) / 1.055) ** 2.4;
}

function relativeLuminance([r, g, b]: [number, number, number]): number {
  return (
    0.2126 * srgbChannelToLinear(r) +
    0.7152 * srgbChannelToLinear(g) +
    0.0722 * srgbChannelToLinear(b)
  );
}

function contrastRatio(hexA: string, hexB: string): number {
  const lumA = relativeLuminance(hexToRgb(hexA));
  const lumB = relativeLuminance(hexToRgb(hexB));
  const lighter = Math.max(lumA, lumB);
  const darker = Math.min(lumA, lumB);
  return (lighter + 0.05) / (darker + 0.05);
}

/** `color-mix(in srgb, fg pct%, transparent)` composited over an opaque backdrop -- the literal
 * pixel colour a reader's eye receives where the stylesheet paints a translucent fill. */
function mixOverBackdrop(fgHex: string, percent: number, backdropHex: string): string {
  const fg = hexToRgb(fgHex);
  const bg = hexToRgb(backdropHex);
  const alpha = percent / 100;
  const mixed = fg.map((channel, i) => Math.round(channel * alpha + bg[i] * (1 - alpha))) as [
    number,
    number,
    number,
  ];
  return `#${mixed.map((c) => c.toString(16).padStart(2, '0')).join('')}`;
}

const MIN_TEXT_CONTRAST = 4.5;
const MIN_UI_CONTRAST = 3.0;
const FEELING_GROUPS = ['uplifted', 'steady', 'tense', 'low'] as const;

describe('feeling-hue composites clear their WCAG target', () => {
  for (const combo of combos) {
    for (const group of FEELING_GROUPS) {
      const feeling = combo.feelings[group];

      it(
        `${group}: border/dot on the chip's own ${CHIP_FILL_PERCENT}% fill -- ` +
          `${combo.name} (base.css .chip--selected / .feeling-dot, >= ${MIN_UI_CONTRAST}:1)`,
        () => {
          const fill = mixOverBackdrop(feeling, CHIP_FILL_PERCENT, combo.surface);
          const ratio = contrastRatio(feeling, fill);
          expect(
            ratio,
            `${group} in ${combo.name} measured ${ratio.toFixed(2)}:1 against its own ` +
              `${CHIP_FILL_PERCENT}% fill, below the ${MIN_UI_CONTRAST}:1 target.`,
          ).toBeGreaterThanOrEqual(MIN_UI_CONTRAST);
        },
      );

      it(
        `${group}: as text/border on the card surface -- ${combo.name} ` +
          `(base.css .entry-card__feeling / .feeling-dialog, >= ${MIN_TEXT_CONTRAST}:1)`,
        () => {
          const ratio = contrastRatio(feeling, combo.surfaceContainer);
          expect(
            ratio,
            `${group} in ${combo.name} measured ${ratio.toFixed(2)}:1 on --color-surface-` +
              `container, below the ${MIN_TEXT_CONTRAST}:1 target.`,
          ).toBeGreaterThanOrEqual(MIN_TEXT_CONTRAST);
        },
      );

      it(
        `${group}: badge text on a full-strength feeling background -- ${combo.name} ` +
          `(base.css .chip--group .chip__count, >= ${MIN_TEXT_CONTRAST}:1)`,
        () => {
          const ratio = contrastRatio(combo.surfaceContainer, feeling);
          expect(
            ratio,
            `--color-surface-container as text on ${group} in ${combo.name} measured ` +
              `${ratio.toFixed(2)}:1, below the ${MIN_TEXT_CONTRAST}:1 target.`,
          ).toBeGreaterThanOrEqual(MIN_TEXT_CONTRAST);
        },
      );
    }
  }
});
