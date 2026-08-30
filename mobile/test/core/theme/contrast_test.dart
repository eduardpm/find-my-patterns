// Contrast audit for every meaningful foreground/background token pair in
// `JournalColors`, across all six palette combinations (three papers ×
// light/dark). This is the regression guard #149 asks for: a future token
// edit that drops a pair below its WCAG target fails here before it ships.
//
// Pairs are not invented in the abstract -- each one is a fact about a real
// call site, found by reading the widgets that paint it: `EntryCard` and
// `JournalCard` fill their card surface from `surfaceContainer`; the
// group-picker sheet in `feeling_chips.dart` fills from `surface`;
// `_colorSchemeFrom` in `app_theme.dart` routes `onSurfaceVariant` onto
// `surfaceContainer` (Material's `secondary`/`onSecondary` slot),
// `onSurface` onto `surfaceVariant`, `primaryContainer` and
// `accentContainer` (`onSecondaryContainer`/`onPrimaryContainer`/
// `onTertiaryContainer`), and `surface` onto `onSurface` for the inverse
// surface Material's default `SnackBar` paints with; `primary`, `accent` and
// `error` are painted directly as text/icon colour on a plain surface at
// several call sites (`day_summary_card.dart`, `insights_screen.dart`,
// `login_screen.dart`); `success`/`successContainer` pair the same way in
// `pattern_card.dart` and `when_panel.dart`.
//
// `FeelingChip` (`lib/core/widgets/feeling_chips.dart`) is the pair the
// palette file's own comment calls out by name: a feeling accent is always
// painted as text, and for a *selected* chip (`FeelingChipVariant
// .selectable`, `selected: true`) the same accent also fills the chip's own
// background at `color.withValues(alpha: 0.12)`. That is not the raw accent
// colour -- it is the accent blended 12% into whatever surface sits behind
// the chip -- so this file computes the ratio against the *composited*
// colour, not the token alone. This test owns no dependency on
// `core/widgets` (that package is #150's, concurrently, per #149's
// out-of-scope section): the 12% figure and the surface/surfaceContainer
// backgrounds are duplicated here as plain constants rather than imported.
//
// Ratios are computed with `Color.computeLuminance`, which already
// implements the WCAG 2.x relative-luminance formula, and the standard
// `(lighter + 0.05) / (darker + 0.05)` contrast formula -- not asserted from
// the palette file's own "inherited from the web tokens" claim, which is
// exactly what measuring here found wrong for two pairs (see the top-of-file
// comment in `journal_palette.dart`).

import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The WCAG 2.x contrast ratio between two colours, order-independent.
double _contrastRatio(Color a, Color b) {
  final luminanceA = a.computeLuminance();
  final luminanceB = b.computeLuminance();
  final lighter = luminanceA > luminanceB ? luminanceA : luminanceB;
  final darker = luminanceA > luminanceB ? luminanceB : luminanceA;
  return (lighter + 0.05) / (darker + 0.05);
}

/// [foreground] painted at [alpha] over an opaque [background] -- the actual
/// pixel colour a reader sees where a widget composites with
/// `Color.withValues(alpha: ...)` rather than painting an opaque fill.
/// `Color.lerp(background, foreground, alpha)` is exactly that: `alpha == 0`
/// is pure background, `alpha == 1` is pure foreground, and every value in
/// between is the linear blend alpha-over-opaque compositing produces.
Color _composited({
  required Color foreground,
  required Color background,
  required double alpha,
}) => Color.lerp(background, foreground, alpha)!;

/// Body and label text's target, per this file's own header comment and
/// WCAG 2.x's "AA" threshold for normal-size text.
const _minTextContrast = 4.5;

/// A non-text UI component boundary's target (the `outline` field only --
/// `hairline` is documented in `journal_palette.dart` as a separator that
/// never bounds a control, so it carries no contrast target of its own).
const _minOutlineContrast = 3.0;

/// The alpha a selected `FeelingChip` fills its background with. See this
/// file's header comment for why it is duplicated here rather than imported.
const _chipFillAlpha = 0.12;

/// One foreground/background token pair to check, named for the failure
/// message and traceable back to the real call site that paints it.
class _Pair {
  const _Pair(this.label, this.foreground, this.background, this.minRatio);

  final String label;
  final Color Function(JournalColors) foreground;
  final Color Function(JournalColors) background;
  final double minRatio;
}

final _textPairs = <_Pair>[
  _Pair(
    'onSurface on surface (body text)',
    (c) => c.onSurface,
    (c) => c.surface,
    _minTextContrast,
  ),
  _Pair(
    'onSurface on surfaceContainer (body text on a card)',
    (c) => c.onSurface,
    (c) => c.surfaceContainer,
    _minTextContrast,
  ),
  _Pair(
    'onSurface on surfaceVariant (onSecondaryContainer slot)',
    (c) => c.onSurface,
    (c) => c.surfaceVariant,
    _minTextContrast,
  ),
  _Pair(
    'onSurface on primaryContainer (onPrimaryContainer slot)',
    (c) => c.onSurface,
    (c) => c.primaryContainer,
    _minTextContrast,
  ),
  _Pair(
    'onSurface on accentContainer (onTertiaryContainer slot)',
    (c) => c.onSurface,
    (c) => c.accentContainer,
    _minTextContrast,
  ),
  _Pair(
    'onSurfaceVariant on surface (muted label text, e.g. '
    '"fewer than 3 entries")',
    (c) => c.onSurfaceVariant,
    (c) => c.surface,
    _minTextContrast,
  ),
  _Pair(
    'onSurfaceVariant on surfaceContainer (secondary slot on a card)',
    (c) => c.onSurfaceVariant,
    (c) => c.surfaceContainer,
    _minTextContrast,
  ),
  _Pair(
    'onSurfaceVariant on surfaceVariant',
    (c) => c.onSurfaceVariant,
    (c) => c.surfaceVariant,
    _minTextContrast,
  ),
  _Pair(
    'onPrimary on primary (filled buttons)',
    (c) => c.onPrimary,
    (c) => c.primary,
    _minTextContrast,
  ),
  _Pair(
    'onPrimary on error (Material onError slot, filled error controls)',
    (c) => c.onPrimary,
    (c) => c.error,
    _minTextContrast,
  ),
  _Pair(
    'onErrorContainer on errorContainer',
    (c) => c.onErrorContainer,
    (c) => c.errorContainer,
    _minTextContrast,
  ),
  _Pair(
    'primary as text on surface (e.g. DaySummaryCard, InsightsScreen)',
    (c) => c.primary,
    (c) => c.surface,
    _minTextContrast,
  ),
  _Pair(
    'primary as text on surfaceContainer',
    (c) => c.primary,
    (c) => c.surfaceContainer,
    _minTextContrast,
  ),
  _Pair(
    'accent as text/icon on surface (e.g. InsightsScreen "guessing" icon)',
    (c) => c.accent,
    (c) => c.surface,
    _minTextContrast,
  ),
  _Pair(
    'accent as text/icon on surfaceContainer',
    (c) => c.accent,
    (c) => c.surfaceContainer,
    _minTextContrast,
  ),
  _Pair(
    'error as text on surface (e.g. LoginScreen, ExportRow)',
    (c) => c.error,
    (c) => c.surface,
    _minTextContrast,
  ),
  _Pair(
    'error as text on surfaceContainer',
    (c) => c.error,
    (c) => c.surfaceContainer,
    _minTextContrast,
  ),
  _Pair(
    'success as text on surface (e.g. PatternCard)',
    (c) => c.success,
    (c) => c.surface,
    _minTextContrast,
  ),
  _Pair(
    'success as text on successContainer (WhenPanel)',
    (c) => c.success,
    (c) => c.successContainer,
    _minTextContrast,
  ),
  _Pair(
    'surface on onSurface (Material inverseSurface/onInverseSurface -- '
    'default SnackBar)',
    (c) => c.surface,
    (c) => c.onSurface,
    _minTextContrast,
  ),
];

final _outlinePairs = <_Pair>[
  _Pair(
    'outline on surface',
    (c) => c.outline,
    (c) => c.surface,
    _minOutlineContrast,
  ),
  _Pair(
    'outline on surfaceContainer',
    (c) => c.outline,
    (c) => c.surfaceContainer,
    _minOutlineContrast,
  ),
];

final _feelingPicks = <String, Color Function(FeelingColors)>{
  'uplifted': (f) => f.uplifted,
  'steady': (f) => f.steady,
  'tense': (f) => f.tense,
  'low': (f) => f.low,
};

final _feelingBackgrounds = <String, Color Function(JournalColors)>{
  'surface': (c) => c.surface,
  'surfaceContainer': (c) => c.surfaceContainer,
};

void main() {
  final combinations = <String, JournalColors>{
    for (final palette in JournalPalette.values) ...{
      '${palette.id} / light': palette.light,
      '${palette.id} / dark': palette.dark,
    },
  };

  group('body and label text clears 4.5:1', () {
    for (final pair in _textPairs) {
      for (final combination in combinations.entries) {
        test('${pair.label} -- ${combination.key}', () {
          final journal = combination.value;
          final ratio = _contrastRatio(
            pair.foreground(journal),
            pair.background(journal),
          );
          expect(
            ratio,
            greaterThanOrEqualTo(pair.minRatio),
            reason:
                '${pair.label} in ${combination.key} measured '
                '${ratio.toStringAsFixed(2)}:1, below the '
                '${pair.minRatio}:1 target.',
          );
        });
      }
    }
  });

  group('outlines clear 3:1', () {
    for (final pair in _outlinePairs) {
      for (final combination in combinations.entries) {
        test('${pair.label} -- ${combination.key}', () {
          final journal = combination.value;
          final ratio = _contrastRatio(
            pair.foreground(journal),
            pair.background(journal),
          );
          expect(
            ratio,
            greaterThanOrEqualTo(pair.minRatio),
            reason:
                '${pair.label} in ${combination.key} measured '
                '${ratio.toStringAsFixed(2)}:1, below the '
                '${pair.minRatio}:1 target.',
          );
        });
      }
    }
  });

  group(
    'feeling hues clear 4.5:1 as text -- directly on a surface, and inside '
    "a selected FeelingChip's own tinted fill",
    () {
      for (final combination in combinations.entries) {
        final journal = combination.value;
        for (final feeling in _feelingPicks.entries) {
          final foreground = feeling.value(journal.feelings);
          for (final background in _feelingBackgrounds.entries) {
            final backgroundColor = background.value(journal);

            test(
              '${feeling.key} on ${background.key} -- ${combination.key}',
              () {
                final ratio = _contrastRatio(foreground, backgroundColor);
                expect(
                  ratio,
                  greaterThanOrEqualTo(_minTextContrast),
                  reason:
                      '${feeling.key} on ${background.key} in '
                      '${combination.key} measured '
                      '${ratio.toStringAsFixed(2)}:1, below the '
                      '$_minTextContrast:1 target.',
                );
              },
            );

            test(
              '${feeling.key} on ${background.key} at '
              '${(_chipFillAlpha * 100).round()}% fill (selected chip) '
              '-- ${combination.key}',
              () {
                final composited = _composited(
                  foreground: foreground,
                  background: backgroundColor,
                  alpha: _chipFillAlpha,
                );
                final ratio = _contrastRatio(foreground, composited);
                expect(
                  ratio,
                  greaterThanOrEqualTo(_minTextContrast),
                  reason:
                      '${feeling.key} text on its own '
                      '${(_chipFillAlpha * 100).round()}% fill over '
                      '${background.key} in ${combination.key} measured '
                      '${ratio.toStringAsFixed(2)}:1, below the '
                      '$_minTextContrast:1 target.',
                );
              },
            );
          }
        }
      }
    },
  );
}
