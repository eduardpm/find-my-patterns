/// @docImport 'app_theme.dart';
library;

import 'package:flutter/material.dart';

/*
 * The web client's split, ported: a serif for the things a person reads
 * (page titles, their own diary prose) and a sans for the things they
 * operate (nav, buttons, labels, numbers).
 *
 * No font binaries. The web client rules out third-party requests and ships
 * no assets; this side keeps that by naming the platform families directly
 * rather than depending on a font package, so 'serif' resolves to whatever
 * serif the OS ships and the app adds nothing to its size. Sizes are the web
 * scale at 1rem = 16, which lands body text at 17 — this app's core act is
 * reading prose, not scanning chrome.
 *
 * Flutter expresses line height as a multiplier of the font size rather than
 * as an absolute value, so every `height` below is `lineHeight ÷ fontSize`
 * from the original web/Kotlin scale — the comment on each style keeps the
 * two numbers the conversion was done from visible.
 */

const String _serifFamily = 'serif';
const String _sansFamily = 'sans-serif';

/// Builds the journal's [TextTheme]: a serif for reading, a sans for
/// everything else, at the web client's scale.
///
/// Named as a builder rather than a constant so it stays a plain function
/// call from [buildLightTheme] and [buildDarkTheme] — the same reason
/// [buildLightTheme] itself is a function and not a precomputed [ThemeData].
TextTheme buildJournalTextTheme() => const TextTheme(
  // The month average on the calendar screen — the one genuinely
  // display-sized number. 36/36.
  displaySmall: TextStyle(
    fontFamily: _serifFamily,
    fontWeight: FontWeight.w600,
    fontSize: 36,
    height: 36 / 36,
    letterSpacing: -0.4,
  ),
  // Page titles: "Today", "Insights". 28/35.
  headlineSmall: TextStyle(
    fontFamily: _serifFamily,
    fontWeight: FontWeight.w600,
    fontSize: 28,
    height: 35 / 28,
    letterSpacing: -0.3,
  ),
  // Card headings: a pattern's topic, an empty state's title. 21/28.
  titleLarge: TextStyle(
    fontFamily: _serifFamily,
    fontWeight: FontWeight.w600,
    fontSize: 21,
    height: 28 / 21,
    letterSpacing: -0.2,
  ),
  // 17/24.
  titleMedium: TextStyle(
    fontFamily: _sansFamily,
    fontWeight: FontWeight.w700,
    fontSize: 17,
    height: 24 / 17,
    letterSpacing: 0,
  ),
  // 17/28.
  bodyLarge: TextStyle(
    fontFamily: _sansFamily,
    fontWeight: FontWeight.w400,
    fontSize: 17,
    height: 28 / 17,
    letterSpacing: 0,
  ),
  // 15/22.
  bodyMedium: TextStyle(
    fontFamily: _sansFamily,
    fontWeight: FontWeight.w400,
    fontSize: 15,
    height: 22 / 15,
    letterSpacing: 0,
  ),
  // 14/20.
  labelLarge: TextStyle(
    fontFamily: _sansFamily,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    height: 20 / 14,
    letterSpacing: 0,
  ),
  // 13/18.
  labelMedium: TextStyle(
    fontFamily: _sansFamily,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 18 / 13,
    letterSpacing: 0,
  ),
  // 12/16.
  labelSmall: TextStyle(
    fontFamily: _sansFamily,
    fontWeight: FontWeight.w600,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0,
  ),
);

/// The styles Material's type scale has no slot for.
abstract final class JournalType {
  /// The reading face: an entry's own words, a pattern's narrative — the
  /// places where the web client switches to its serif. Using
  /// [TextTheme.bodyLarge] for these would set a person's diary in the same
  /// sans as the buttons around it. 17/28.
  static const TextStyle prose = TextStyle(
    fontFamily: _serifFamily,
    fontWeight: FontWeight.w400,
    fontSize: 17,
    height: 28 / 17,
    letterSpacing: 0,
  );

  /// The tracked, upper-cased label above a title ("MONDAY, AUGUST 24", "3
  /// ENTRIES"). Callers pass ordinary text and [eyebrowCase] does the
  /// upper-casing, so the string itself is never mutated on the way to an
  /// accessibility service — see [eyebrowCase]. 12/16.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: _sansFamily,
    fontWeight: FontWeight.w600,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0.96,
  );

  /// Adds tabular figures to [style], for times, counts and averages, so
  /// digits don't jitter as values change.
  static TextStyle tabularFigures(TextStyle style) =>
      style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// Upper-cases [text] for display only.
  ///
  /// The result is for painting, never for the accessibility tree: the
  /// `Eyebrow` widget passes the caller's original casing to `Semantics`
  /// and only feeds this through to the [Text] it paints.
  static String eyebrowCase(String text) => text.toUpperCase();
}
