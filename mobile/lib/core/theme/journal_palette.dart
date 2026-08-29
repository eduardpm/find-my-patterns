/// @docImport 'app_theme.dart';
library;

import 'package:flutter/material.dart';

/*
 * The palettes are a value-for-value port of the web client's `tokens.css`
 * and the Kotlin `theme/Color.kt`. They used to be a single Material 3
 * wallpaper-derived dynamic scheme, which meant the app's brand changed from
 * phone to phone and shared nothing with the other clients but its data. All
 * three clients are now the same journal: same surfaces, same three papers,
 * same four feeling hues. A diary read on a desk and on a phone reading as
 * one product is worth more here than matching whatever wallpaper the phone
 * happens to wear.
 *
 * There are three papers rather than one: `paper` (the original warm cream),
 * `sage` and `dusk`, chosen in Settings and stored on the device. They are
 * alternative papers to write on, not three brands -- each keeps the same
 * three surface depths, the same serif/sans split, and the same restraint
 * about saturation.
 *
 * Every palette is a *pair*. The light and dark halves were designed
 * together rather than one being derived from the other, because inverting a
 * warm page gives a cold one, and because no single hue clears its contrast
 * target against both a near-white and a near-black surface.
 *
 * Contrast was inherited from the web tokens, where every pair was checked
 * against its intended surface: body and label text clears 4.5:1, outlines
 * clear 3:1, and the feeling hues clear 4.5:1 because they tint text as well
 * as dots.
 */

/// The accent per feeling *group*, for calendar dots, the rail down an entry
/// card, and chip selection.
///
/// One accent per group, not per feeling. The feeling vocabulary has grown
/// past thirty words, and thirty hues that tell apart at the size of a
/// calendar dot do not exist -- inventing them would make the calendar less
/// legible, not more. Four do, and every feeling in a group carries that
/// group's valence, so tinting a whole group with one accent asserts nothing
/// the backend did not say.
///
/// Deliberately decoupled from the domain layer: lookups are keyed on the
/// plain strings the backend sends (`groupKey`, `valenceId`) rather than on a
/// `Feeling` or `FeelingGroup` type, so `core/theme` never has to import
/// `core/diary`.
@immutable
final class const FeelingColors({
  required final Color uplifted,
  required final Color steady,
  required final Color tense,
  required final Color low,
}) {
  /// The colour for a feeling group's key, or `null` for a group this build
  /// has never seen.
  Color? forGroupKey(String? groupKey) => switch (groupKey) {
    'uplifted' => uplifted,
    'steady' => steady,
    'tense' => tense,
    'low' => low,
    _ => null,
  };

  /// The fallback accent for an unrecognised group, chosen from the valence
  /// the backend did tell us about.
  Color forValenceId(String? valenceId) => switch (valenceId) {
    'positive' => uplifted,
    'negative' => low,
    _ => steady,
  };

  /// The accent for a feeling, given whatever the caller has on hand.
  ///
  /// Tries [forGroupKey] first; if the group is one this build has never
  /// seen, falls back to [forValenceId]. This is the entry point most
  /// callers should reach for: a feeling group the backend gained after this
  /// build shipped still gets a readable colour, and the app needs no
  /// release to cope with a new feeling or a new group.
  Color forFeeling({String? groupKey, String? valenceId}) =>
      forGroupKey(groupKey) ?? forValenceId(valenceId);

  /// A copy of these colours with the given fields replaced.
  FeelingColors copyWith({
    Color? uplifted,
    Color? steady,
    Color? tense,
    Color? low,
  }) => FeelingColors(
    uplifted: uplifted ?? this.uplifted,
    steady: steady ?? this.steady,
    tense: tense ?? this.tense,
    low: low ?? this.low,
  );

  /// Linear interpolation between two sets of feeling colours, for
  /// [JournalColors.lerp].
  static FeelingColors lerp(FeelingColors a, FeelingColors b, double t) =>
      FeelingColors(
        uplifted: Color.lerp(a.uplifted, b.uplifted, t)!,
        steady: Color.lerp(a.steady, b.steady, t)!,
        tense: Color.lerp(a.tense, b.tense, t)!,
        low: Color.lerp(a.low, b.low, t)!,
      );
}

/// A smooth colour ramp from a negative day score through neutral to a
/// positive one, for any chart built on the day score CH-0's `GET
/// /insights/series` serves (`score`, on the -1..+1 scale
/// `VALENCE_SCORE` defines in the backend's `constants.ts`).
///
/// Defined once here, next to the palette tokens, so every chart that reads
/// a day score — the mood line, Year in Pixels, and later the topic
/// sparkline — draws it through the same three-stop ramp instead of each
/// inventing its own gradient. [FeelingColors] already carries the three
/// stops this needs ([FeelingColors.low], [FeelingColors.steady],
/// [FeelingColors.uplifted]), so the ramp is an extension on it rather than
/// a fourth colour set to keep in sync.
extension ValenceRamp on FeelingColors {
  /// The ramp colour for [score], clamped to -1..1 before interpolating.
  ///
  /// A negative score interpolates between [steady] (at 0) and [low] (at
  /// -1); a non-negative score interpolates between [steady] (at 0) and
  /// [uplifted] (at 1). [steady] is the ramp's fixed midpoint, so a score of
  /// exactly 0 reads identically whichever half it is approached from, and
  /// the ramp never needs a fourth "true zero" colour of its own.
  Color colorForScore(double score) {
    final clamped = score.clamp(-1.0, 1.0);
    return clamped < 0
        ? Color.lerp(steady, low, -clamped)!
        : Color.lerp(steady, uplifted, clamped)!;
  }
}

/// One half of one palette: every colour the app draws with, at one
/// lightness.
///
/// A [ThemeExtension] so a widget reaches it the same way it reaches
/// [ThemeData.colorScheme] — `Theme.of(context).extension<JournalColors>()`,
/// or the null-safe `context.journalColors` accessor. It is also the source
/// [buildLightTheme] and [buildDarkTheme] fill Material's own
/// [ColorScheme] from, for the tokens Material has a slot for, and the value
/// behind the tokens it does not: the hairline that only separates (as
/// opposed to [outline], which bounds real controls), the advisory [accent],
/// the [success] pair, and the feeling hues.
@immutable
final class const JournalColors({
  required final Color surface,
  required final Color surfaceContainer,
  required final Color surfaceVariant,
  required final Color onSurface,
  required final Color onSurfaceVariant,
  required final Color primary,
  required final Color onPrimary,
  required final Color primaryContainer,
  required final Color accent,
  required final Color accentContainer,
  required final Color outline,
  required final Color hairline,
  required final Color error,
  required final Color errorContainer,
  required final Color onErrorContainer,
  required final Color success,
  required final Color successContainer,
  required final FeelingColors feelings,
  required final bool isDark,
}) extends ThemeExtension<JournalColors> {
  /// A copy of these colours with the given fields replaced.
  @override
  JournalColors copyWith({
    Color? surface,
    Color? surfaceContainer,
    Color? surfaceVariant,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? accent,
    Color? accentContainer,
    Color? outline,
    Color? hairline,
    Color? error,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? success,
    Color? successContainer,
    FeelingColors? feelings,
    bool? isDark,
  }) => JournalColors(
    surface: surface ?? this.surface,
    surfaceContainer: surfaceContainer ?? this.surfaceContainer,
    surfaceVariant: surfaceVariant ?? this.surfaceVariant,
    onSurface: onSurface ?? this.onSurface,
    onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    primaryContainer: primaryContainer ?? this.primaryContainer,
    accent: accent ?? this.accent,
    accentContainer: accentContainer ?? this.accentContainer,
    outline: outline ?? this.outline,
    hairline: hairline ?? this.hairline,
    error: error ?? this.error,
    errorContainer: errorContainer ?? this.errorContainer,
    onErrorContainer: onErrorContainer ?? this.onErrorContainer,
    success: success ?? this.success,
    successContainer: successContainer ?? this.successContainer,
    feelings: feelings ?? this.feelings,
    isDark: isDark ?? this.isDark,
  );

  /// Interpolates between two [JournalColors], as [ThemeExtension] requires
  /// for an animated [ThemeData] transition.
  ///
  /// Falls back to `this` when [other] is not a [JournalColors]: the
  /// contract only promises a same-typed value, and there is nothing
  /// sensible to interpolate towards otherwise.
  @override
  JournalColors lerp(ThemeExtension<JournalColors>? other, double t) {
    if (other is! JournalColors) return this;
    return JournalColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceContainer: Color.lerp(
        surfaceContainer,
        other.surfaceContainer,
        t,
      )!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceVariant: Color.lerp(
        onSurfaceVariant,
        other.onSurfaceVariant,
        t,
      )!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primaryContainer: Color.lerp(
        primaryContainer,
        other.primaryContainer,
        t,
      )!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onErrorContainer: Color.lerp(
        onErrorContainer,
        other.onErrorContainer,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      feelings: FeelingColors.lerp(feelings, other.feelings, t),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

const _paperLight = JournalColors(
  surface: Color(0xFFFBF7F0),
  surfaceContainer: Color(0xFFFFFFFF),
  surfaceVariant: Color(0xFFF3ECE1),
  onSurface: Color(0xFF231C14),
  onSurfaceVariant: Color(0xFF6A5C4C),
  primary: Color(0xFF92400E),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFF6E8D5),
  accent: Color(0xFF4F46E5),
  accentContainer: Color(0xFFECEBFD),
  outline: Color(0xFF8E8373),
  hairline: Color(0xFFE6DCCC),
  error: Color(0xFFB3261E),
  errorContainer: Color(0xFFFDECEA),
  onErrorContainer: Color(0xFF8C1D18),
  success: Color(0xFF1B5E20),
  successContainer: Color(0xFFE6F0E6),
  feelings: FeelingColors(
    uplifted: Color(0xFF2A7430),
    steady: Color(0xFF5F5F5F),
    tense: Color(0xFFB3441A),
    low: Color(0xFF3F4BA8),
  ),
  isDark: false,
);

const _paperDark = JournalColors(
  surface: Color(0xFF17130F),
  surfaceContainer: Color(0xFF211B15),
  surfaceVariant: Color(0xFF2A231B),
  onSurface: Color(0xFFF2EAE0),
  onSurfaceVariant: Color(0xFFBCAB98),
  primary: Color(0xFFE8A857),
  onPrimary: Color(0xFF231C14),
  primaryContainer: Color(0xFF3A2A17),
  accent: Color(0xFFA5B4FC),
  accentContainer: Color(0xFF262647),
  outline: Color(0xFF7E6C58),
  hairline: Color(0xFF3F342B),
  error: Color(0xFFF2B8B5),
  errorContainer: Color(0xFF48211F),
  onErrorContainer: Color(0xFFF9DEDC),
  success: Color(0xFFA5D6A7),
  successContainer: Color(0xFF1E2E1F),
  feelings: FeelingColors(
    uplifted: Color(0xFF7CC47F),
    steady: Color(0xFFB4A99B),
    tense: Color(0xFFFF9E70),
    low: Color(0xFF93A0EC),
  ),
  isDark: true,
);

const _sageLight = JournalColors(
  surface: Color(0xFFF4F6F1),
  surfaceContainer: Color(0xFFFFFFFF),
  surfaceVariant: Color(0xFFE7EEE3),
  onSurface: Color(0xFF1B241C),
  onSurfaceVariant: Color(0xFF556356),
  primary: Color(0xFF2F6146),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFDBE9DE),
  accent: Color(0xFF9A5426),
  accentContainer: Color(0xFFF6E7DA),
  outline: Color(0xFF7C8C7D),
  hairline: Color(0xFFDAE3D6),
  error: Color(0xFFB3261E),
  errorContainer: Color(0xFFFBEAE8),
  onErrorContainer: Color(0xFF8C1D18),
  success: Color(0xFF26643C),
  successContainer: Color(0xFFDFEBDF),
  feelings: FeelingColors(
    uplifted: Color(0xFF2A7430),
    steady: Color(0xFF5B635C),
    tense: Color(0xFFA8451C),
    low: Color(0xFF3D4F9C),
  ),
  isDark: false,
);

const _sageDark = JournalColors(
  surface: Color(0xFF10150F),
  surfaceContainer: Color(0xFF1A211A),
  surfaceVariant: Color(0xFF232B22),
  onSurface: Color(0xFFE6EDE2),
  onSurfaceVariant: Color(0xFFA8B7A5),
  primary: Color(0xFF8FC79B),
  onPrimary: Color(0xFF12251A),
  primaryContainer: Color(0xFF24382A),
  accent: Color(0xFFE0A97A),
  accentContainer: Color(0xFF3A2A1E),
  outline: Color(0xFF6D7C6C),
  hairline: Color(0xFF2E382C),
  error: Color(0xFFF2B8B5),
  errorContainer: Color(0xFF46201F),
  onErrorContainer: Color(0xFFF9DEDC),
  success: Color(0xFFA5D6A7),
  successContainer: Color(0xFF1C2C1D),
  feelings: FeelingColors(
    uplifted: Color(0xFF84CC8B),
    steady: Color(0xFFADB9AB),
    tense: Color(0xFFF5A07A),
    low: Color(0xFF9AA8EE),
  ),
  isDark: true,
);

const _duskLight = JournalColors(
  surface: Color(0xFFF4F5FA),
  surfaceContainer: Color(0xFFFFFFFF),
  surfaceVariant: Color(0xFFE9EBF3),
  onSurface: Color(0xFF1B1D2A),
  onSurfaceVariant: Color(0xFF575D72),
  primary: Color(0xFF3B4A7A),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFE0E4F3),
  accent: Color(0xFF87406B),
  accentContainer: Color(0xFFF4E6EF),
  outline: Color(0xFF7B8298),
  hairline: Color(0xFFDCDFEA),
  error: Color(0xFFB3261E),
  errorContainer: Color(0xFFFCECEB),
  onErrorContainer: Color(0xFF8C1D18),
  success: Color(0xFF1B5E20),
  successContainer: Color(0xFFE5EFE7),
  feelings: FeelingColors(
    uplifted: Color(0xFF2F7355),
    steady: Color(0xFF5C6172),
    tense: Color(0xFFA94523),
    low: Color(0xFF3F4BA8),
  ),
  isDark: false,
);

const _duskDark = JournalColors(
  surface: Color(0xFF101220),
  surfaceContainer: Color(0xFF191C2C),
  surfaceVariant: Color(0xFF222537),
  onSurface: Color(0xFFE8E9F4),
  onSurfaceVariant: Color(0xFFADB3C9),
  primary: Color(0xFFA3B6F2),
  onPrimary: Color(0xFF161A2E),
  primaryContainer: Color(0xFF2A3050),
  accent: Color(0xFFE39BC4),
  accentContainer: Color(0xFF3A2434),
  outline: Color(0xFF737A94),
  hairline: Color(0xFF313650),
  error: Color(0xFFF2B8B5),
  errorContainer: Color(0xFF46212A),
  onErrorContainer: Color(0xFFF9DEDC),
  success: Color(0xFFA5D6A7),
  successContainer: Color(0xFF1D2E22),
  feelings: FeelingColors(
    uplifted: Color(0xFF7FCAA4),
    steady: Color(0xFFB9B8BD),
    tense: Color(0xFFF9A17F),
    low: Color(0xFF9FB0F5),
  ),
  isDark: true,
);

/// The three papers, in the order Settings offers them.
///
/// [id] is what gets written to disk, so it is a stable string rather than
/// the enum's `name` — renaming a constant must not silently reset someone's
/// choice. It is also the same id the web and Android clients store, which
/// is not required but means one vocabulary describes every client.
enum JournalPalette {
  /// Cream and journal brown, with ink violet for anything the diary is
  /// guessing at.
  paper(
    id: 'paper',
    label: 'Warm paper',
    description:
        'Cream and journal brown, with ink violet for anything the diary '
        'is guessing at.',
    light: _paperLight,
    dark: _paperDark,
  ),

  /// A greener page and a pine ink. The quietest of the three.
  sage(
    id: 'sage',
    label: 'Sage',
    description: 'A greener page and a pine ink. The quietest of the three.',
    light: _sageLight,
    dark: _sageDark,
  ),

  /// Cool grey-blue and deep indigo, for writing late with the lights still
  /// on.
  dusk(
    id: 'dusk',
    label: 'Dusk',
    description:
        'Cool grey-blue and deep indigo, for writing late with the lights '
        'still on.',
    light: _duskLight,
    dark: _duskDark,
  );

  const JournalPalette({
    required this.id,
    required this.label,
    required this.description,
    required this.light,
    required this.dark,
  });

  /// The value written to device storage.
  ///
  /// A stable string rather than an ordinal or `Enum.name`: an ordinal would
  /// re-point someone's choice at a different paper the moment the list is
  /// reordered, and a name would break if a constant is ever renamed. An id
  /// is a value that changes only when someone changes it on purpose.
  final String id;

  /// The human-readable name shown in Settings.
  final String label;

  /// A sentence describing the paper, shown under [label] in Settings.
  final String description;

  /// This palette's light half.
  final JournalColors light;

  /// This palette's dark half.
  final JournalColors dark;

  /// This palette's light or dark half, matching [dark].
  JournalColors colors({required bool dark}) => dark ? this.dark : light;

  /// The palette the app opens on before Settings has loaded, and the one a
  /// stored id falls back to when it is not recognised.
  static const JournalPalette defaultPalette = JournalPalette.paper;

  /// The palette with the given [id], or [defaultPalette] if unrecognised.
  ///
  /// Falls back rather than throwing: a downgrade, or a build that dropped a
  /// palette, must open on the warm paper the app has always started with
  /// instead of refusing to draw.
  static JournalPalette fromId(String? id) =>
      JournalPalette.values.where((palette) => palette.id == id).firstOrNull ??
      defaultPalette;
}
