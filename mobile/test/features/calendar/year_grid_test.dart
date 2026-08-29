// Coverage for the Year in Pixels grid (CH-2): the pure cell-generation and
// geometry logic `yearGridCells`/`dateAtIndex`/`YearGridGeometry` are unit
// tested directly rather than through pixel assertions on the painted
// output, and the accessibility summary/tooltip text generators the same
// way -- this repo's Article 3 forbids styling assertions and there is no
// golden-image harness (see `calendar_day_cell_test.dart`'s own header
// comment for the same call). "Correct cell count per month" is the
// `yearGridCells` group below; "tap routing" and "forward clamp" are the
// `YearGrid` widget-test groups, which drive the actual rendered widget
// end to end using the exact geometry `YearGridGeometry.forWidth` computes
// (proving the wiring, not re-proving the geometry math its own group
// already covers). "Verified on all 3 papers x light/dark" is the
// `every paper, light and dark` group: it pumps the grid under each and
// asserts it renders without throwing and keeps exposing its semantics
// summary, the same two things `calendar_day_cell_test.dart` asserts for
// the month grid's own per-palette coverage.

import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/mood_series.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/theme/journal_metrics.dart';
import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:find_my_patterns/features/calendar/calendar_controller.dart';
import 'package:find_my_patterns/features/calendar/year_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

/// Builds a [MoodSeriesPoint] directly, for the pure-logic groups below that
/// operate on domain objects rather than wire JSON (the widget-test group
/// further down goes through the real [seriesJson]/[seriesPointJson] wire
/// fixtures instead, over a [FakeHttpAdapter]).
MoodSeriesPoint seriesPointFromJsonForTest(
  String date, {
  double? score = 1,
  int entryCount = 1,
  int confirmedFeelingCount = 1,
}) => MoodSeriesPoint(
  CalendarDate.parse(date),
  score,
  entryCount,
  confirmedFeelingCount,
);

void main() {
  group('dateAtIndex', () {
    test('resolves a real date from 0-based month/day indices', () {
      expect(dateAtIndex(2026, 0, 0), const CalendarDate(2026, 1, 1));
      expect(dateAtIndex(2026, 11, 30), const CalendarDate(2026, 12, 31));
    });

    test('a day past a short month\'s length is null — no Feb 30', () {
      expect(dateAtIndex(2026, 1, 29), isNull); // Feb 30th, 2026
      expect(dateAtIndex(2026, 3, 30), isNull); // April 31st
    });

    test('a leap year gives February 29 a real date', () {
      expect(dateAtIndex(2024, 1, 28), const CalendarDate(2024, 2, 29));
    });

    test('a non-leap year does not', () {
      expect(dateAtIndex(2026, 1, 28), isNull);
    });

    test('an out-of-range month index is null', () {
      expect(dateAtIndex(2026, -1, 0), isNull);
      expect(dateAtIndex(2026, 12, 0), isNull);
    });
  });

  group('yearGridCells', () {
    test('produces exactly the days each month actually has', () {
      final cells = yearGridCells(2026, const []);
      final byMonth = <int, int>{};
      for (final cell in cells) {
        byMonth[cell.date.month] = (byMonth[cell.date.month] ?? 0) + 1;
      }
      expect(byMonth[1], 31);
      expect(byMonth[2], 28); // 2026 is not a leap year.
      expect(byMonth[3], 31);
      expect(byMonth[4], 30);
      expect(byMonth[5], 31);
      expect(byMonth[6], 30);
      expect(byMonth[7], 31);
      expect(byMonth[8], 31);
      expect(byMonth[9], 30);
      expect(byMonth[10], 31);
      expect(byMonth[11], 30);
      expect(byMonth[12], 31);
      expect(cells, hasLength(365));
    });

    test('a leap year produces 29 February cells, 366 in total', () {
      final cells = yearGridCells(2024, const []);
      expect(cells.where((c) => c.date.month == 2).length, 29);
      expect(cells, hasLength(366));
    });

    test('never produces a non-existent date', () {
      final cells = yearGridCells(2026, const []);
      expect(
        cells.where((c) => c.date.month == 2 && c.date.day == 30),
        isEmpty,
      );
    });

    test('attaches the matching point by date, leaving the rest null', () {
      final point = seriesPointFromJsonForTest('2026-08-05');
      final cells = yearGridCells(2026, [point]);
      final august5 = cells.firstWhere(
        (c) => c.date == const CalendarDate(2026, 8, 5),
      );
      final august6 = cells.firstWhere(
        (c) => c.date == const CalendarDate(2026, 8, 6),
      );
      expect(august5.point, same(point));
      expect(august6.point, isNull);
    });

    test('indices are 0-based and line up with the date', () {
      final cells = yearGridCells(2026, const []);
      final jan1 = cells.first;
      expect(jan1.monthIndex, 0);
      expect(jan1.dayIndex, 0);
      final dec31 = cells.last;
      expect(dec31.monthIndex, 11);
      expect(dec31.dayIndex, 30);
    });
  });

  group('YearGridGeometry', () {
    test('forWidth divides evenly into 12 columns with the fixed spacing', () {
      final geometry = YearGridGeometry.forWidth(368);
      expect(geometry.cellSize, closeTo((368 - 2 * 11) / 12, 1e-9));
      expect(geometry.spacing, 2);
      expect(geometry.size.width, closeTo(368, 1e-6));
    });

    test('cellSize never drops below 1, even for a near-zero width', () {
      final geometry = YearGridGeometry.forWidth(0);
      expect(geometry.cellSize, greaterThanOrEqualTo(1));
    });

    test('rectOf and cellIndexAt round-trip through a cell\'s centre', () {
      final geometry = YearGridGeometry.forWidth(368);
      for (final index in [(0, 0), (5, 15), (11, 30)]) {
        final (month, day) = index;
        final rect = geometry.rectOf(month, day);
        expect(geometry.cellIndexAt(rect.center), index);
      }
    });

    test('a position in the gap between two cells resolves to no cell', () {
      final geometry = YearGridGeometry.forWidth(368);
      final gapPoint = Offset(geometry.cellSize + geometry.spacing / 2, 5);
      expect(geometry.cellIndexAt(gapPoint), isNull);
    });

    test('a position outside the grid entirely resolves to no cell', () {
      final geometry = YearGridGeometry.forWidth(368);
      expect(geometry.cellIndexAt(const Offset(-1, 0)), isNull);
      expect(
        geometry.cellIndexAt(Offset(geometry.size.width + 10, 0)),
        isNull,
      );
      expect(
        geometry.cellIndexAt(Offset(0, geometry.size.height + 10)),
        isNull,
      );
    });
  });

  group('yearGridSummary', () {
    test('no days written yet', () {
      expect(yearGridSummary(2026, const []), '2026: no days written yet');
    });

    test('singular "day" for exactly one', () {
      final points = [seriesPointFromJsonForTest('2026-08-05', score: null)];
      expect(yearGridSummary(2026, points), '2026: 1 day written');
    });

    test('days written with no scored points at all states only the count', () {
      final points = [
        seriesPointFromJsonForTest('2026-08-05', score: null),
        seriesPointFromJsonForTest('2026-08-06', score: null),
      ];
      expect(yearGridSummary(2026, points), '2026: 2 days written');
    });

    test('names the run of positive months up to the latest scored month', () {
      final points = [
        seriesPointFromJsonForTest('2026-03-01', score: -1), // negative
        seriesPointFromJsonForTest('2026-06-01', score: 1),
        seriesPointFromJsonForTest('2026-07-01', score: 1),
        seriesPointFromJsonForTest('2026-08-01', score: 1),
      ];
      expect(
        yearGridSummary(2026, points),
        '2026: 4 days written, mostly positive since June',
      );
    });

    test('names a run of negative months the same way', () {
      final points = [
        seriesPointFromJsonForTest('2026-01-01', score: 1),
        seriesPointFromJsonForTest('2026-11-01', score: -1),
        seriesPointFromJsonForTest('2026-12-01', score: -1),
      ];
      expect(
        yearGridSummary(2026, points),
        '2026: 3 days written, mostly negative since November',
      );
    });

    test('the run stops at the most recent month with a different sign', () {
      final points = [
        seriesPointFromJsonForTest('2026-01-01', score: 1),
        seriesPointFromJsonForTest('2026-02-01', score: -1),
        seriesPointFromJsonForTest('2026-03-01', score: 1),
      ];
      expect(
        yearGridSummary(2026, points),
        '2026: 3 days written, mostly positive since March',
      );
    });

    test(
      'a most-recent scored month averaging exactly zero omits the clause',
      () {
        final points = [
          seriesPointFromJsonForTest('2026-01-01', score: 1),
          seriesPointFromJsonForTest('2026-06-01', score: 1),
          seriesPointFromJsonForTest('2026-06-02', score: -1),
        ];
        expect(yearGridSummary(2026, points), '2026: 3 days written');
      },
    );
  });

  group('cellTooltipText', () {
    const date = CalendarDate(2026, 8, 5);

    test('a day with no entries', () {
      expect(
        cellTooltipText(date, null, isToday: false),
        'Aug 5, 2026: no entries',
      );
    });

    test('today is called out', () {
      expect(
        cellTooltipText(date, null, isToday: true),
        'Aug 5, 2026 (today): no entries',
      );
    });

    test('a positive score', () {
      final point = seriesPointFromJsonForTest(
        '2026-08-05',
        score: 1,
        entryCount: 2,
      );
      expect(
        cellTooltipText(date, point, isToday: false),
        'Aug 5, 2026: 2 entries, positive',
      );
    });

    test('a negative score', () {
      final point = seriesPointFromJsonForTest('2026-08-05', score: -1);
      expect(
        cellTooltipText(date, point, isToday: false),
        'Aug 5, 2026: 1 entry, negative',
      );
    });

    test('a neutral score', () {
      final point = seriesPointFromJsonForTest('2026-08-05', score: 0);
      expect(
        cellTooltipText(date, point, isToday: false),
        'Aug 5, 2026: 1 entry, neutral',
      );
    });

    test('entries with no confirmed feeling read as unconfirmed', () {
      final point = seriesPointFromJsonForTest('2026-08-05', score: null);
      expect(
        cellTooltipText(date, point, isToday: false),
        'Aug 5, 2026: 1 entry, unconfirmed',
      );
    });
  });

  group('YearGrid widget', () {
    final fixedNow = DateTime(2026, 8, 15);

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
      void Function(CalendarDate)? onOpenDay,
      double width = 400,
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
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: YearGrid(onOpenDay: onOpenDay),
          ),
        ),
      ),
    );

    /// The width [LayoutBuilder] sees once [width] passes through
    /// [YearGrid]'s year switcher's column and [JournalCard]'s own
    /// content padding.
    double contentWidth(double width) => width - JournalSpacing.x4 * 2;

    testWidgets('shows a spinner, then the year header once loaded', (
      tester,
    ) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter([FakeReply(200, body: seriesJson())]),
      );
      await tester.pumpWidget(app(harness));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('2026'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('a failed fetch shows the error as a snack bar', (
      tester,
    ) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter([
          FakeReply(500, body: {'error': 'boom'}),
        ]),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      expect(find.text('boom'), findsOneWidget);
      // hasLoaded still flips, so the grid renders empty rather than
      // spinning forever over a failure.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets(
      'exposes the accessibility summary as the grid\'s own semantics label',
      (tester) async {
        useTallScreen(tester);
        final handle = tester.ensureSemantics();
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(
              200,
              body: seriesJson(
                points: [seriesPointJson(date: '2026-08-05', score: 1)],
              ),
            ),
          ]),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();

        expect(
          find.bySemanticsLabel(
            '2026: 1 day written, mostly positive since August',
          ),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets('tapping a cell opens the day it represents', (tester) async {
      useTallScreen(tester);
      CalendarDate? opened;
      final harness = configuredHarness(
        FakeHttpAdapter([FakeReply(200, body: seriesJson())]),
      );
      await tester.pumpWidget(
        app(harness, onOpenDay: (date) => opened = date),
      );
      await tester.pumpAndSettle();

      final geometry = YearGridGeometry.forWidth(contentWidth(400));
      final topLeft = tester.getTopLeft(
        find.byKey(const Key('yearGridPaintArea')),
      );
      // August (index 7), the 5th (index 4).
      final target = topLeft + geometry.rectOf(7, 4).center;
      await tester.tapAt(target);
      await tester.pumpAndSettle();

      expect(opened, const CalendarDate(2026, 8, 5));
    });

    testWidgets('tapping the gap between two cells opens nothing', (
      tester,
    ) async {
      useTallScreen(tester);
      CalendarDate? opened;
      final harness = configuredHarness(
        FakeHttpAdapter([FakeReply(200, body: seriesJson())]),
      );
      await tester.pumpWidget(
        app(harness, onOpenDay: (date) => opened = date),
      );
      await tester.pumpAndSettle();

      final geometry = YearGridGeometry.forWidth(contentWidth(400));
      final topLeft = tester.getTopLeft(
        find.byKey(const Key('yearGridPaintArea')),
      );
      final gapPoint =
          topLeft + Offset(geometry.cellSize + geometry.spacing / 2, 5);
      await tester.tapAt(gapPoint);
      await tester.pumpAndSettle();

      expect(opened, isNull);
    });

    testWidgets(
      'long-pressing a cell shows its tooltip text; releasing hides it',
      (tester) async {
        useTallScreen(tester);
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(
              200,
              body: seriesJson(
                points: [
                  seriesPointJson(
                    date: '2026-08-05',
                    score: 1,
                    entryCount: 2,
                  ),
                ],
              ),
            ),
          ]),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();

        final geometry = YearGridGeometry.forWidth(contentWidth(400));
        final topLeft = tester.getTopLeft(
          find.byKey(const Key('yearGridPaintArea')),
        );
        final target = topLeft + geometry.rectOf(7, 4).center;

        final gesture = await tester.startGesture(target);
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.text('Aug 5, 2026: 2 entries, positive'), findsOneWidget);

        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.text('Aug 5, 2026: 2 entries, positive'), findsNothing);
      },
    );

    testWidgets('the forward chevron is disabled on the current year', (
      tester,
    ) async {
      useTallScreen(tester);
      final handle = tester.ensureSemantics();
      final harness = configuredHarness(
        FakeHttpAdapter([FakeReply(200, body: seriesJson())]),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      final nextButton = tester.widget<IconButton>(
        find.descendant(
          of: find.bySemanticsLabel('Next year'),
          matching: find.byType(IconButton),
        ),
      );
      expect(nextButton.onPressed, isNull);
      handle.dispose();
    });

    testWidgets(
      'the year switcher moves back and forward, clamped at the current year',
      (tester) async {
        useTallScreen(tester);
        final handle = tester.ensureSemantics();
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: seriesJson()),
            FakeReply(200, body: seriesJson()),
            FakeReply(200, body: seriesJson()),
          ]),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();
        expect(find.text('2026'), findsOneWidget);

        await tester.tap(find.bySemanticsLabel('Previous year'));
        await tester.pumpAndSettle();
        expect(find.text('2025'), findsOneWidget);

        await tester.tap(find.bySemanticsLabel('Next year'));
        await tester.pumpAndSettle();
        expect(find.text('2026'), findsOneWidget);

        // Already on the current year: the button is disabled, so this
        // reaches the same forward clamp `year_grid_controller_test.dart`
        // proves directly — no third request is made and the year holds.
        await tester.tap(
          find.bySemanticsLabel('Next year'),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(find.text('2026'), findsOneWidget);
        handle.dispose();
      },
    );

    group('every paper, light and dark', () {
      for (final palette in JournalPalette.values) {
        for (final dark in [false, true]) {
          final theming = dark ? 'dark' : 'light';
          testWidgets('renders the grid on ${palette.id} $theming', (
            tester,
          ) async {
            useTallScreen(tester);
            final harness = configuredHarness(
              FakeHttpAdapter([
                FakeReply(
                  200,
                  body: seriesJson(
                    points: [
                      seriesPointJson(date: '2026-01-05', score: 1),
                      seriesPointJson(date: '2026-06-10', score: null),
                    ],
                  ),
                ),
              ]),
            );
            final handle = tester.ensureSemantics();
            await tester.pumpWidget(
              app(harness, palette: palette, dark: dark),
            );
            await tester.pumpAndSettle();

            // Renders without throwing under this palette/theme, the year
            // header and the painted grid are both present, and the grid
            // still exposes its own accessibility summary — the
            // structural/behavioural check this file makes for the
            // palette x theme matrix; colour itself is never asserted, per
            // this repo's Article 3.
            expect(find.text('2026'), findsOneWidget);
            expect(find.byType(CustomPaint), findsWidgets);
            expect(
              find.bySemanticsLabel(RegExp(r'^2026: 2 days written')),
              findsOneWidget,
            );
            handle.dispose();
          });
        }
      }
    });
  });
}
