// Widget coverage for the calendar day cell's UX-9b rework: dropping the
// dashed border on empty days, and the entry-volume proxy bar under a
// logged day's dots.
//
// There is no golden-image harness in this repo (see `calendar_screen.dart`
// and `feeling_chip_test.dart` for the same call), so "verified on all 3
// papers x light/dark" here means two things instead of six screenshots:
//   * a widget test per paper/theme combination that pumps a day cell of
//     each kind (empty and logged) and asserts the treatment it renders —
//     no dashed border anywhere, the empty day's dimmed number colour, the
//     logged day's fill, dots and volume-bar width; and
//   * a pure contrast-ratio check, in the same style as
//     `feeling_chip_test.dart`'s valence-colour group, proving the colours
//     those widgets are given actually clear WCAG's text (4.5:1) and
//     non-text (3:1) minimums in every palette's both halves.
//
// `GET /monthly-summary` has no per-day entry count (see
// `calendar_screen.dart`'s `_DayCell` doc comment) — `days[].feelings` is
// the distinct *set* of feeling keys logged that day, not one entry per
// slot — so the volume bar reads `feelings.length` instead. This file uses
// a six-key catalog, local to it, to exercise that mapping past its
// five-feeling ceiling; `json_fixtures.dart`'s shared three-key catalog
// stays untouched since nothing else in this suite needs more than that.

import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:find_my_patterns/core/widgets/journal.dart';
import 'package:find_my_patterns/core/widgets/journal_dashed_border.dart';
import 'package:find_my_patterns/features/calendar/calendar_controller.dart';
import 'package:find_my_patterns/features/calendar/calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

/// Six single-letter feeling keys, all in one group — the catalog only
/// needs enough distinct keys to push the volume bar past its five-feeling
/// ceiling, not a realistic vocabulary.
const _sixFeelingKeys = ['a', 'b', 'c', 'd', 'e', 'f'];

Map<String, Object?> _feelingJson(String key) => {
  'key': key,
  'label': key.toUpperCase(),
  'valence': 'positive',
  'group_key': 'uplifted',
};

Map<String, Object?> _richCatalogJson() => {
  'feelings': [for (final key in _sixFeelingKeys) _feelingJson(key)],
  'groups': [
    {
      'key': 'uplifted',
      'label': 'Uplifted',
      'valence': 'positive',
      'feelings': [for (final key in _sixFeelingKeys) _feelingJson(key)],
    },
  ],
};

/// The WCAG contrast ratio between two colours — the same formula
/// `feeling_chip_test.dart`'s own helper uses for the 4.5:1 text rule.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final brighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (brighter + 0.05) / (darker + 0.05);
}

void main() {
  final fixedNow = DateTime(2026, 8, 15);

  /// See `calendar_screen_test.dart`'s identically-named helper: a plain
  /// `ListView`'s sliver only materializes children within the viewport.
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Harness configuredHarness(FakeHttpAdapter adapter) => Harness(
    settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
    adapter: adapter,
  );

  Widget app(
    Harness harness, {
    JournalPalette palette = JournalPalette.paper,
    bool dark = false,
  }) => ProviderScope(
    overrides: [
      requireAuthProvider.overrideWithValue(harness.requireAuth),
      settingsStoreProvider.overrideWithValue(harness.store),
      apiClientProvider.overrideWithValue(harness.client),
      calendarNowProvider.overrideWithValue(fixedNow),
    ],
    child: MaterialApp(
      theme: buildLightTheme(palette: palette),
      darkTheme: buildDarkTheme(palette: palette),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: const CalendarScreen(),
    ),
  );

  /// The rendered width factor of the day cell keyed `calendarVolumeBar-
  /// <date>`'s fill.
  double volumeWidthFactor(WidgetTester tester, String date) => tester
      .widget<FractionallySizedBox>(
        find.descendant(
          of: find.byKey(ValueKey('calendarVolumeBar-$date')),
          matching: find.byType(FractionallySizedBox),
        ),
      )
      .widthFactor!;

  group('empty days', () {
    testWidgets(
      'draw no border at all — the dashed outline is gone, not swapped',
      (tester) async {
        useTallScreen(tester);
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: feelingsCatalogJson()),
            FakeReply(200, body: monthlySummaryJson(month: '2026-08')),
          ]),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();

        // No cell in the whole grid draws the dashed empty-state outline —
        // it is dropped, not swapped for a plain solid border.
        expect(find.byType(DashedBorder), findsNothing);

        // Day 6's cell wraps nothing in a DecoratedBox: no fill, no
        // border, dashed or otherwise. Only its own dimmed number sits on
        // the plain page. Contrast with the logged-day test below, whose
        // cell does wrap its content in one.
        final emptyCell = find.byKey(
          const ValueKey('calendarDayCell-2026-08-06'),
        );
        expect(emptyCell, findsOneWidget);
        expect(
          find.descendant(of: emptyCell, matching: find.byType(DecoratedBox)),
          findsNothing,
        );
      },
    );

    testWidgets('the number is dimmed via onSurfaceVariant, not a literal', (
      tester,
    ) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          FakeReply(200, body: monthlySummaryJson(month: '2026-08')),
        ]),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      final number = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('calendarDayCell-2026-08-06')),
          matching: find.text('6'),
        ),
      );
      final theme = Theme.of(tester.element(find.byType(CalendarScreen)));
      expect(number.style!.color, theme.colorScheme.onSurfaceVariant);
    });
  });

  group('the volume bar', () {
    testWidgets(
      'widens with the distinct-feeling count, one fifth per feeling, '
      'capping at five',
      (tester) async {
        useTallScreen(tester);
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: _richCatalogJson()),
            FakeReply(
              200,
              body: monthlySummaryJson(
                month: '2026-08',
                days: [
                  for (var n = 1; n <= 6; n++)
                    daySummaryJson(
                      date: '2026-08-0$n',
                      feelings: _sixFeelingKeys.take(n).toList(),
                    ),
                ],
              ),
            ),
          ]),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();

        expect(volumeWidthFactor(tester, '2026-08-01'), closeTo(0.2, 1e-6));
        expect(volumeWidthFactor(tester, '2026-08-02'), closeTo(0.4, 1e-6));
        expect(volumeWidthFactor(tester, '2026-08-03'), closeTo(0.6, 1e-6));
        expect(volumeWidthFactor(tester, '2026-08-04'), closeTo(0.8, 1e-6));
        expect(volumeWidthFactor(tester, '2026-08-05'), closeTo(1.0, 1e-6));
        // Six distinct feelings still reads as "full", not overflowing —
        // this is the "10+-entry day" acceptance criterion's proxy case.
        expect(volumeWidthFactor(tester, '2026-08-06'), closeTo(1.0, 1e-6));
      },
    );

    testWidgets(
      'a 1-feeling day and a 5-feeling day are visibly different widths',
      (tester) async {
        useTallScreen(tester);
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: _richCatalogJson()),
            FakeReply(
              200,
              body: monthlySummaryJson(
                month: '2026-08',
                days: [
                  daySummaryJson(date: '2026-08-01', feelings: const ['a']),
                  daySummaryJson(
                    date: '2026-08-02',
                    feelings: _sixFeelingKeys,
                  ),
                ],
              ),
            ),
          ]),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();

        expect(
          volumeWidthFactor(tester, '2026-08-02'),
          greaterThan(volumeWidthFactor(tester, '2026-08-01')),
        );
      },
    );
  });

  group('dots', () {
    testWidgets('stay capped at three even with more feelings logged', (
      tester,
    ) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter([
          FakeReply(200, body: _richCatalogJson()),
          FakeReply(
            200,
            body: monthlySummaryJson(
              month: '2026-08',
              days: [
                daySummaryJson(
                  date: '2026-08-05',
                  feelings: _sixFeelingKeys,
                ),
              ],
            ),
          ),
        ]),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      final loggedCell = find.byKey(
        const ValueKey('calendarDayCell-2026-08-05'),
      );
      expect(
        find.descendant(of: loggedCell, matching: find.byType(FeelingDot)),
        findsNWidgets(3),
      );
    });
  });

  group('semantics', () {
    testWidgets('never states an entry count the payload does not carry', (
      tester,
    ) async {
      useTallScreen(tester);
      final handle = tester.ensureSemantics();
      final harness = configuredHarness(
        FakeHttpAdapter([
          FakeReply(200, body: _richCatalogJson()),
          FakeReply(
            200,
            body: monthlySummaryJson(
              month: '2026-08',
              days: [
                daySummaryJson(
                  date: '2026-08-05',
                  feelings: _sixFeelingKeys,
                  intensity: 4,
                ),
              ],
            ),
          ),
        ]),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      // Every distinct feeling logged is still named in full — a screen
      // reader is told strictly more than the sighted volume bar shows.
      expect(
        find.bySemanticsLabel('5, A, B, C, D, E, F, intensity 4'),
        findsOneWidget,
      );
      // No cell anywhere in the grid claims a number of entries.
      expect(find.bySemanticsLabel(RegExp(r'\d+ entries?\b')), findsNothing);
      handle.dispose();
    });
  });

  group('every paper, light and dark', () {
    for (final palette in JournalPalette.values) {
      for (final dark in [false, true]) {
        final theming = dark ? 'dark' : 'light';

        testWidgets(
          'renders the empty-day and logged-day treatment on '
          '${palette.id} $theming',
          (tester) async {
            useTallScreen(tester);
            final harness = configuredHarness(
              FakeHttpAdapter([
                FakeReply(200, body: feelingsCatalogJson()),
                FakeReply(
                  200,
                  body: monthlySummaryJson(
                    month: '2026-08',
                    days: [
                      daySummaryJson(
                        date: '2026-08-05',
                        feelings: const ['happy', 'sad'],
                        intensity: 3,
                      ),
                    ],
                  ),
                ),
              ]),
            );
            await tester.pumpWidget(
              app(harness, palette: palette, dark: dark),
            );
            await tester.pumpAndSettle();

            final colors = palette.colors(dark: dark);

            // Empty day: still no dashed border, and the dimmed number is
            // this palette/theme's own onSurfaceVariant.
            expect(find.byType(DashedBorder), findsNothing);
            final emptyNumber = tester.widget<Text>(
              find.descendant(
                of: find.byKey(
                  const ValueKey('calendarDayCell-2026-08-06'),
                ),
                matching: find.text('6'),
              ),
            );
            expect(emptyNumber.style!.color, colors.onSurfaceVariant);

            // Logged day: two dots, and a volume bar at 40% (2 of 5
            // feelings) filled with this palette/theme's own primary.
            final loggedCell = find.byKey(
              const ValueKey('calendarDayCell-2026-08-05'),
            );
            expect(
              find.descendant(
                of: loggedCell,
                matching: find.byType(FeelingDot),
              ),
              findsNWidgets(2),
            );
            expect(
              volumeWidthFactor(tester, '2026-08-05'),
              closeTo(0.4, 1e-6),
            );
            final volumeFill = tester.widgetList<ColoredBox>(
              find.descendant(
                of: find.byKey(
                  const ValueKey('calendarVolumeBar-2026-08-05'),
                ),
                matching: find.byType(ColoredBox),
              ),
            );
            expect(
              volumeFill.map((box) => box.color),
              contains(colors.primary),
            );
          },
        );
      }
    }

    test(
      "the empty day's dimmed number clears 4.5:1 against the card surface "
      'it sits on',
      () {
        for (final palette in JournalPalette.values) {
          for (final dark in [false, true]) {
            final colors = palette.colors(dark: dark);
            final ratio = _contrastRatio(
              colors.onSurfaceVariant,
              colors.surfaceContainer,
            );
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '${palette.id} ${dark ? 'dark' : 'light'}: '
                  '${colors.onSurfaceVariant} on ${colors.surfaceContainer} '
                  'only clears ${ratio.toStringAsFixed(2)}:1',
            );
          }
        }
      },
    );

    test(
      "the volume bar's fill clears 3:1 against a logged cell's own fill",
      () {
        for (final palette in JournalPalette.values) {
          for (final dark in [false, true]) {
            final colors = palette.colors(dark: dark);
            final ratio = _contrastRatio(colors.primary, colors.surfaceVariant);
            expect(
              ratio,
              greaterThanOrEqualTo(3.0),
              reason:
                  '${palette.id} ${dark ? 'dark' : 'light'}: '
                  '${colors.primary} on ${colors.surfaceVariant} only '
                  'clears ${ratio.toStringAsFixed(2)}:1',
            );
          }
        }
      },
    );

    test('every feeling dot clears 3:1 against a logged cell\'s own fill', () {
      for (final palette in JournalPalette.values) {
        for (final dark in [false, true]) {
          final colors = palette.colors(dark: dark);
          final hues = [
            colors.feelings.uplifted,
            colors.feelings.steady,
            colors.feelings.tense,
            colors.feelings.low,
          ];
          for (final hue in hues) {
            final ratio = _contrastRatio(hue, colors.surfaceVariant);
            expect(
              ratio,
              greaterThanOrEqualTo(3.0),
              reason:
                  '${palette.id} ${dark ? 'dark' : 'light'}: $hue on '
                  '${colors.surfaceVariant} only clears '
                  '${ratio.toStringAsFixed(2)}:1',
            );
          }
        }
      }
    });
  });
}
