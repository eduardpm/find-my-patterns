// Widget coverage for the "THIS MONTH" totals panel's feeling-mix stacked
// bar (CH-3, issue #31): one horizontal bar above the existing per-feeling
// count list, segments proportional to counts, colours matching the list's
// own swatches, tiny segments merged into a trailing "other" bucket.
//
// There is no golden-image harness in this repo (see `calendar_screen.dart`
// and `calendar_day_cell_test.dart` for the same call), so "verified on all
// 3 papers x light/dark" here means a widget test per paper/theme
// combination that pumps the bar and asserts its segment colours match that
// palette/theme's own tokens, the same approach `calendar_day_cell_test.dart`
// uses for the day cell.
//
// The bar reads `Expanded.flex` values directly for "proportional to
// counts" rather than measuring pixel widths: `_FeelingMixBar` builds each
// segment as an `Expanded(flex: count, ...)` inside one `Row`, so a
// segment's rendered width is exactly `flex / totalFlex` of the bar's own
// width by construction — asserting the flex values is a precise,
// resolution-independent way to check the same thing tester.getSize would,
// without depending on the surface size a particular test happens to use.

import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:find_my_patterns/core/widgets/journal.dart';
import 'package:find_my_patterns/features/calendar/calendar_controller.dart';
import 'package:find_my_patterns/features/calendar/calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

/// Thirty single-use feeling keys — just enough that every one of them can
/// sit under the ~4% merge floor at once (100% / 30 ≈ 3.3% apiece), which
/// the shared 3-feeling `feelingsCatalogJson()` fixture can never do (three
/// shares summing to 100% always leave at least one well above 4%). Local
/// to this file's "entirely other" edge case, same rationale as
/// `calendar_day_cell_test.dart`'s own local six-key catalog.
final List<String> _manyFeelingKeys = [
  for (var i = 0; i < 30; i++) 'f$i',
];

Map<String, Object?> _manyFeelingsCatalogJson() => {
  'feelings': [
    for (final key in _manyFeelingKeys)
      {
        'key': key,
        'label': key.toUpperCase(),
        'valence': 'positive',
        'group_key': 'uplifted',
      },
  ],
  'groups': const <Object?>[],
};

void main() {
  final fixedNow = DateTime(2026, 8, 15);

  /// See `calendar_screen_test.dart`'s identically-named helper: a plain
  /// `ListView`'s sliver only materializes children within the viewport, so
  /// the totals panel — below the grid — never builds without this.
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

  final barFinder = find.byKey(const ValueKey('feelingMixBar'));

  /// The bar's segments' `Expanded.flex` values, in paint order.
  List<int> segmentFlexes(WidgetTester tester) => tester
      .widgetList<Expanded>(
        find.descendant(of: barFinder, matching: find.byType(Expanded)),
      )
      .map((expanded) => expanded.flex)
      .toList();

  /// The bar's segments' fill colours, in paint order.
  List<Color> segmentColors(WidgetTester tester) => tester
      .widgetList<ColoredBox>(
        find.descendant(of: barFinder, matching: find.byType(ColoredBox)),
      )
      .map((box) => box.color)
      .toList();

  /// The colour of the [FeelingDot] swatch on the count-list row labelled
  /// [label] — the closest [Row] ancestor of that row's [Text] is the inner
  /// `Row(children: [FeelingDot, ..., Text(label)])` [_TotalsPanel] builds,
  /// so its own [FeelingDot] descendant is this row's swatch.
  Color rowSwatchColor(WidgetTester tester, String label) {
    final row = find
        .ancestor(of: find.text(label), matching: find.byType(Row))
        .first;
    return tester
        .widget<FeelingDot>(
          find.descendant(of: row, matching: find.byType(FeelingDot)),
        )
        .color;
  }

  group('proportional widths, no merge', () {
    testWidgets(
      'segment flexes match counts, in backend order',
      (tester) async {
        useTallScreen(tester);
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: feelingsCatalogJson()),
            FakeReply(
              200,
              body: monthlySummaryJson(
                month: '2026-08',
                totalsByFeeling: const {'happy': 6, 'sad': 3, 'anxious': 1},
              ),
            ),
          ]),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();

        expect(barFinder, findsOneWidget);
        // Every count clears the ~4% merge threshold at this total (10),
        // so no "other" segment appears and the catalog's own (backend)
        // order — happy, sad, anxious — survives untouched.
        expect(segmentFlexes(tester), [6, 3, 1]);
      },
    );

    testWidgets(
      'row swatches match their own segment colour when nothing merged',
      (tester) async {
        useTallScreen(tester);
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: feelingsCatalogJson()),
            FakeReply(
              200,
              body: monthlySummaryJson(
                month: '2026-08',
                totalsByFeeling: const {'happy': 6, 'sad': 3, 'anxious': 1},
              ),
            ),
          ]),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();

        final colors = JournalPalette.paper.colors(dark: false);
        expect(
          rowSwatchColor(tester, 'Happy'),
          colors.feelings.uplifted,
        );
        expect(rowSwatchColor(tester, 'Sad'), colors.feelings.low);
        expect(rowSwatchColor(tester, 'Anxious'), colors.feelings.tense);
        expect(segmentColors(tester), [
          colors.feelings.uplifted,
          colors.feelings.low,
          colors.feelings.tense,
        ]);
      },
    );
  });

  group('the ~4% merge rule', () {
    testWidgets(
      'segments under ~4% of the total merge into one trailing "other", '
      'appended last regardless of backend order',
      (tester) async {
        useTallScreen(tester);
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: feelingsCatalogJson()),
            FakeReply(
              200,
              // sad (3%) and anxious (1%) both fall under the ~4% floor;
              // both merge into a single trailing segment sized 4 (3 + 1),
              // even though they are not adjacent in backend order.
              body: monthlySummaryJson(
                month: '2026-08',
                totalsByFeeling: const {'happy': 96, 'sad': 3, 'anxious': 1},
              ),
            ),
          ]),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();

        expect(segmentFlexes(tester), [96, 4]);

        final colors = JournalPalette.paper.colors(dark: false);
        expect(segmentColors(tester), [
          colors.feelings.uplifted,
          colors.onSurfaceVariant,
        ]);

        // The count list keeps listing every feeling individually — it is
        // the precise, accessible form the bar's own merge must not hide.
        // (Their exact counts are covered by the semantics test below,
        // which states them unambiguously; a bare `find.text('3')` here
        // would also match day 3's own cell number in the grid above.)
        expect(find.text('Happy'), findsOneWidget);
        expect(find.text('Sad'), findsOneWidget);
        expect(find.text('Anxious'), findsOneWidget);
      },
    );

    testWidgets(
      "a merged row's swatch turns the trailing segment's colour, not its "
      'own valence accent',
      (tester) async {
        useTallScreen(tester);
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: feelingsCatalogJson()),
            FakeReply(
              200,
              body: monthlySummaryJson(
                month: '2026-08',
                totalsByFeeling: const {'happy': 96, 'sad': 3, 'anxious': 1},
              ),
            ),
          ]),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();

        final colors = JournalPalette.paper.colors(dark: false);
        // Happy alone clears the threshold, so its dot stays its own hue.
        expect(rowSwatchColor(tester, 'Happy'), colors.feelings.uplifted);
        // Sad and Anxious were both merged into "other" — their dots turn
        // that segment's neutral colour, not their individual low/tense
        // accents, because that is the paint their count actually landed
        // under on the bar above.
        expect(rowSwatchColor(tester, 'Sad'), colors.onSurfaceVariant);
        expect(rowSwatchColor(tester, 'Anxious'), colors.onSurfaceVariant);
      },
    );

    testWidgets(
      'a month where every feeling is under threshold still draws one bar, '
      'entirely "other"',
      (tester) async {
        useTallScreen(tester);
        // Three feelings can't all fall under ~4%: their shares must sum
        // to 100%, so at least one of three is always well above the
        // floor. This case only exists with a wide enough vocabulary, so
        // this uses a local 30-feeling catalog — one count each, 1/30 ≈
        // 3.3% apiece — rather than the shared 3-feeling fixture.
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: _manyFeelingsCatalogJson()),
            FakeReply(
              200,
              body: monthlySummaryJson(
                month: '2026-08',
                totalsByFeeling: {
                  for (final key in _manyFeelingKeys) key: 1,
                },
              ),
            ),
          ]),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();

        expect(segmentFlexes(tester), [_manyFeelingKeys.length]);
        final colors = JournalPalette.paper.colors(dark: false);
        expect(segmentColors(tester), [colors.onSurfaceVariant]);
      },
    );
  });

  group('semantics', () {
    testWidgets(
      'states every logged feeling and its exact count, merged or not',
      (tester) async {
        useTallScreen(tester);
        final handle = tester.ensureSemantics();
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: feelingsCatalogJson()),
            FakeReply(
              200,
              body: monthlySummaryJson(
                month: '2026-08',
                totalsByFeeling: const {'happy': 96, 'sad': 3, 'anxious': 1},
              ),
            ),
          ]),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();

        expect(
          find.bySemanticsLabel(
            'Feeling mix this month: Happy 96, Sad 3, Anxious 1',
          ),
          findsOneWidget,
        );
        handle.dispose();
      },
    );
  });

  group('empty month', () {
    testWidgets('draws no bar at all', (tester) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          FakeReply(200, body: monthlySummaryJson(month: '2026-08')),
        ]),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      expect(barFinder, findsNothing);
    });
  });

  group('every paper, light and dark', () {
    for (final palette in JournalPalette.values) {
      for (final dark in [false, true]) {
        final theming = dark ? 'dark' : 'light';

        testWidgets(
          'renders the bar with this palette/theme\'s own tokens on '
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
                    totalsByFeeling: const {
                      'happy': 96,
                      'sad': 3,
                      'anxious': 1,
                    },
                  ),
                ),
              ]),
            );
            await tester.pumpWidget(
              app(harness, palette: palette, dark: dark),
            );
            await tester.pumpAndSettle();

            final colors = palette.colors(dark: dark);
            expect(barFinder, findsOneWidget);
            expect(segmentFlexes(tester), [96, 4]);
            expect(segmentColors(tester), [
              colors.feelings.uplifted,
              colors.onSurfaceVariant,
            ]);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('at 2x text scale', () {
    testWidgets('the bar and the totals panel render with no overflow', (
      tester,
    ) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          FakeReply(
            200,
            body: monthlySummaryJson(
              month: '2026-08',
              totalsByFeeling: const {'happy': 96, 'sad': 3, 'anxious': 1},
              averageEntriesPerDay: 1.4,
            ),
          ),
        ]),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 3000),
            textScaler: TextScaler.linear(2),
          ),
          child: app(harness),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(barFinder, findsOneWidget);
      expect(find.text('Happy'), findsOneWidget);
      expect(find.text('96'), findsOneWidget);
    });
  });
}
