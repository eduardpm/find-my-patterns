import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/calendar/calendar_controller.dart';
import 'package:find_my_patterns/features/calendar/calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

void main() {
  final fixedNow = DateTime(2026, 8, 15);

  /// Gives the test a tall surface so the totals panel — below the grid, and
  /// otherwise below the fold — actually builds. A plain `ListView`'s
  /// sliver only materializes children within the viewport, same as
  /// `settings_screen_test.dart`'s identically-named helper.
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Harness configuredHarness(FakeHttpAdapter adapter) => Harness(
    settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
    adapter: adapter,
  );

  Widget app(Harness harness, {void Function(CalendarDate)? onOpenDay}) =>
      ProviderScope(
        overrides: [
          requireAuthProvider.overrideWithValue(harness.requireAuth),
          settingsStoreProvider.overrideWithValue(harness.store),
          apiClientProvider.overrideWithValue(harness.client),
          calendarNowProvider.overrideWithValue(fixedNow),
        ],
        child: MaterialApp(home: CalendarScreen(onOpenDay: onOpenDay)),
      );

  testWidgets('shows the header, month label and grid once loaded', (
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
            days: [
              daySummaryJson(
                date: '2026-08-05',
                feelings: const ['happy'],
                intensity: 3,
              ),
            ],
            // 99 rather than a small count: August has no day numbered 99,
            // so this can't collide with a day cell's own digit.
            totalsByFeeling: const {'happy': 99},
            averageEntriesPerDay: 0.2,
          ),
        ),
      ]),
    );
    await tester.pumpWidget(app(harness));
    await tester.pumpAndSettle();

    expect(find.text('Calendar'), findsOneWidget);
    // Eyebrow labels render upper-cased for display; the accessible name
    // (checked separately below) carries the natural casing.
    expect(find.text('MONTH AT A GLANCE'), findsOneWidget);
    expect(find.text('August 2026'), findsOneWidget);
    expect(find.text('THIS MONTH'), findsOneWidget);
    expect(find.text('0.2'), findsOneWidget);
    expect(find.text('Happy'), findsOneWidget);
    expect(find.text('99'), findsOneWidget);
  });

  testWidgets(
    'a logged day announces its feelings and intensity; an empty day says so outright',
    (
      tester,
    ) async {
      useTallScreen(tester);
      final handle = tester.ensureSemantics();
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
                  intensity: 4,
                ),
              ],
            ),
          ),
        ]),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('5, Happy, Sad, intensity 4'),
        findsOneWidget,
      );
      // Day 6 has no entries.
      expect(find.bySemanticsLabel('6, no entries'), findsOneWidget);
      handle.dispose();
    },
  );

  testWidgets('a month with nothing logged shows no per-feeling rows', (
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

    expect(find.text('0.0'), findsOneWidget);
    expect(find.text('Happy'), findsNothing);
    expect(find.text('Sad'), findsNothing);
    // CH-3's feeling-mix bar draws nothing for an empty month either — see
    // `feeling_mix_bar_test.dart` for the rest of its coverage.
    expect(find.byKey(const ValueKey('feelingMixBar')), findsNothing);
  });

  testWidgets('tapping a day opens it', (tester) async {
    useTallScreen(tester);
    final handle = tester.ensureSemantics();
    CalendarDate? opened;
    final harness = configuredHarness(
      FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: monthlySummaryJson(
            month: '2026-08',
            days: [
              daySummaryJson(date: '2026-08-05', feelings: const ['happy']),
            ],
          ),
        ),
      ]),
    );
    await tester.pumpWidget(app(harness, onOpenDay: (date) => opened = date));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('5, Happy'));

    expect(opened, const CalendarDate(2026, 8, 5));
    handle.dispose();
  });

  testWidgets(
    'the Month/Year toggle switches between the two grids, and back',
    (tester) async {
      useTallScreen(tester);
      final handle = tester.ensureSemantics();
      final harness = configuredHarness(
        FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          FakeReply(200, body: monthlySummaryJson(month: '2026-08')),
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

      // The month grid is on screen by default.
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.bySemanticsLabel('Next month'), findsOneWidget);

      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();

      // Switching reveals the year grid — its own switcher and its own
      // day-score fetch — and the month grid leaves the tree entirely.
      expect(find.text('August 2026'), findsNothing);
      expect(find.bySemanticsLabel('Next month'), findsNothing);
      expect(find.text('2026'), findsOneWidget);
      expect(find.bySemanticsLabel('Next year'), findsOneWidget);

      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('2026'), findsNothing);
      handle.dispose();
    },
  );

  testWidgets('the month switcher moves forward and back', (tester) async {
    useTallScreen(tester);
    final handle = tester.ensureSemantics();
    final harness = configuredHarness(
      FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(200, body: monthlySummaryJson(month: '2026-08')),
        FakeReply(200, body: monthlySummaryJson(month: '2026-09')),
        FakeReply(200, body: monthlySummaryJson(month: '2026-08')),
      ]),
    );
    await tester.pumpWidget(app(harness));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('resuming reloads whichever month is currently on screen', (
    tester,
  ) async {
    useTallScreen(tester);
    final handle = tester.ensureSemantics();
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsCatalogJson()),
      FakeReply(200, body: monthlySummaryJson(month: '2026-08')),
      FakeReply(200, body: monthlySummaryJson(month: '2026-09')),
      FakeReply(200, body: monthlySummaryJson(month: '2026-09')),
    ]);
    final harness = configuredHarness(adapter);
    await tester.pumpWidget(app(harness));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Next month'));
    await tester.pumpAndSettle();
    final requestsBefore = adapter.requests.length;

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();

    expect(adapter.requests.length, requestsBefore + 1);
    expect(adapter.requests.last.uri.queryParameters['month'], '2026-09');
    handle.dispose();
  });
}
