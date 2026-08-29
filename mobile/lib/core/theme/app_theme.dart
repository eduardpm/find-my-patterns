import 'package:flutter/material.dart';

import '../settings/settings.dart';
import 'journal_palette.dart';
import 'journal_typography.dart';

/// Builds the light theme for [palette].
///
/// Defaults to [JournalPalette.defaultPalette] so every call site that
/// predates the palette setting — including `lib/app.dart` and any preview
/// or test calling this with no arguments — keeps working unchanged.
ThemeData buildLightTheme({
  JournalPalette palette = JournalPalette.defaultPalette,
}) => _themeFor(palette.colors(dark: false));

/// Builds the dark theme for [palette]. See [buildLightTheme].
ThemeData buildDarkTheme({
  JournalPalette palette = JournalPalette.defaultPalette,
}) => _themeFor(palette.colors(dark: true));

ThemeData _themeFor(JournalColors journal) => ThemeData(
  colorScheme: _colorSchemeFrom(journal),
  textTheme: buildJournalTextTheme(),
  extensions: [journal],
);

/// Fills Material's [ColorScheme] from [journal] rather than seeding it from
/// a brand colour.
///
/// Filling every slot the app actually paints through is the point: the app
/// uses stock M3 components (snackbar, text fields, navigation bar), and a
/// slot left at its Material default is how a stray purple appears inside an
/// otherwise brown screen. [ColorScheme.light]/[ColorScheme.dark] supply the
/// Material baseline for everything this palette does not have an opinion
/// about — `surfaceTint`, `shadow`, `scrim`, the "fixed" containers — the
/// same role `lightColorScheme()`/`darkColorScheme()` play as the base for
/// the Kotlin `.copy()` this ports.
///
/// Dynamic colour is deliberately not used, and there is no Material-You
/// wallpaper theming: the three fixed papers are the product's own, and a
/// diary read on a desk and on a phone reading as one product is worth more
/// here than matching the wallpaper behind it.
ColorScheme _colorSchemeFrom(JournalColors journal) {
  final base = journal.isDark
      ? const ColorScheme.dark()
      : const ColorScheme.light();
  return base.copyWith(
    primary: journal.primary,
    onPrimary: journal.onPrimary,
    primaryContainer: journal.primaryContainer,
    onPrimaryContainer: journal.onSurface,
    secondary: journal.onSurfaceVariant,
    onSecondary: journal.surfaceContainer,
    secondaryContainer: journal.surfaceVariant,
    onSecondaryContainer: journal.onSurface,
    tertiary: journal.accent,
    onTertiary: journal.onPrimary,
    tertiaryContainer: journal.accentContainer,
    onTertiaryContainer: journal.onSurface,
    surface: journal.surface,
    onSurface: journal.onSurface,
    surfaceContainer: journal.surfaceContainer,
    surfaceContainerHigh: journal.surfaceContainer,
    surfaceContainerHighest: journal.surfaceVariant,
    surfaceContainerLow: journal.surface,
    surfaceContainerLowest: journal.surface,
    onSurfaceVariant: journal.onSurfaceVariant,
    outline: journal.outline,
    outlineVariant: journal.hairline,
    inverseSurface: journal.onSurface,
    onInverseSurface: journal.surface,
    error: journal.error,
    onError: journal.onPrimary,
    errorContainer: journal.errorContainer,
    onErrorContainer: journal.onErrorContainer,
  );
}

/// Translates the stored [setting] into the Flutter mode it names.
ThemeMode themeModeSettingToMaterial(ThemeModeSetting setting) =>
    switch (setting) {
      ThemeModeSetting.system => ThemeMode.system,
      ThemeModeSetting.light => ThemeMode.light,
      ThemeModeSetting.dark => ThemeMode.dark,
    };

/// Reaches [JournalColors] the same way [ThemeData.colorScheme] is reached,
/// without every call site writing
/// `Theme.of(context).extension<JournalColors>()!`.
///
/// Never returns `null`: if the extension is somehow absent — a test
/// building a bare [ThemeData] without going through [buildLightTheme] or
/// [buildDarkTheme] — this falls back to [JournalPalette.defaultPalette]'s
/// half matching the ambient [Brightness], so a widget can always draw
/// rather than crash.
extension JournalColorsContext on BuildContext {
  /// The colours of the palette currently in force.
  JournalColors get journalColors {
    final theme = Theme.of(this);
    return theme.extension<JournalColors>() ??
        JournalPalette.defaultPalette.colors(
          dark: theme.brightness == Brightness.dark,
        );
  }
}
