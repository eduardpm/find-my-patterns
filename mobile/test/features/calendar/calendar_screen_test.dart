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
        find.bySemanticsLabel('5, 2 entries, Happy, Sad, intensity 4'),
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

    await tester.tap(find.bySemanticsLabel('5, 1 entry, Happy'));

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

  group('dynamic type at 320dp/2x (#150)', () {
    // #150: `GridView.count`'s implicit `childAspectRatio: 1` forced every
    // month-grid cell to stay exactly as tall as it is wide, so at
    // 320dp/2x the day number alone -- before even the dot row and bars a
    // logged day adds underneath it -- no longer fit the cell it was
    // squeezed into. Every cell in the month overflowed at once: 22 to 30
    // cells depending on the fixture, from 7px (an empty day) up to 64px
    // (a logged one). `_CalendarGrid` now measures the day number's own
    // rendered height at the real `TextScaler` (mirroring
    // `today/day_summary_card.dart`'s width measurement) and grows the
    // grid's row height to fit, rather than trusting a hardcoded square.
    testWidgets(
      'a full month with a heavily logged day renders with no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: feelingsCatalogJson()),
            FakeReply(
              200,
              body: monthlySummaryJson(
                month: '2026-08',
                days: [
                  daySummaryJson(
                    date: '2026-08-15',
                    feelings: const ['happy', 'excited', 'grateful'],
                    intensity: 5,
                    entryCount: 12,
                  ),
                ],
                totalsByFeeling: const {'happy': 5},
                averageEntriesPerDay: 1.5,
              ),
            ),
          ]),
        );
        await tester.pumpWidget(
          // `.copyWith` on the *ambient* data (the real one the test's own
          // root `View` derives from `tester.view`), not a fresh
          // `MediaQueryData(textScaler: ...)` -- the latter replaces every
          // other field, including `size`, with its own defaults.
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: app(harness),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // A positive assertion the grid actually rendered its content,
        // pairing the exception check above the way #150's own lesson
        // (seven prior instances of a rendered-nothing false green)
        // requires.
        expect(find.text('15'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
        expect(find.text('31'), findsOneWidget);
      },
    );

    testWidgets('the month switcher wraps a long month name onto a second '
        'line rather than overflowing', (tester) async {
      tester.view.physicalSize = const Size(320, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = configuredHarness(
        FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          // `fixedNow` opens the screen on August; navigating forward is
          // what actually reaches September.
          FakeReply(200, body: monthlySummaryJson(month: '2026-08')),
          FakeReply(200, body: monthlySummaryJson(month: '2026-09')),
        ]),
      );
      await tester.pumpWidget(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: app(harness),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Next month'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('September 2026'), findsOneWidget);
    });

    testWidgets(
      'the weekday header drops to single letters uniformly rather than '
      'letting only "MO" wrap onto two lines (#155)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final handle = tester.ensureSemantics();

        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: feelingsCatalogJson()),
            FakeReply(200, body: monthlySummaryJson(month: '2026-08')),
          ]),
        );
        await tester.pumpWidget(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: app(harness),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // At 320dp/2x, "MO" no longer fits its 1/7 share of the row, so
        // every column drops to a single letter together -- never just the
        // one column whose glyphs happen to be widest.
        expect(find.text('MO'), findsNothing);
        expect(find.text('M'), findsOneWidget);
        expect(find.text('W'), findsOneWidget);
        expect(find.text('F'), findsOneWidget);
        // Every weekday header cell renders at the same height as its
        // siblings -- #155's own defect was "MO" alone wrapping onto a
        // second line while its six neighbours stayed on one.
        final mHeight = tester.getSize(find.text('M')).height;
        final wHeight = tester.getSize(find.text('W')).height;
        final fHeight = tester.getSize(find.text('F')).height;
        expect(wHeight, mHeight);
        expect(fHeight, mHeight);

        // The visible label shrank to a single letter, but the accessible
        // name stays the full weekday -- #150's semantics work must not
        // regress because of a layout fix.
        expect(find.bySemanticsLabel('Monday'), findsOneWidget);
        expect(find.bySemanticsLabel('Tuesday'), findsOneWidget);
        expect(find.bySemanticsLabel('Wednesday'), findsOneWidget);
        expect(find.bySemanticsLabel('Thursday'), findsOneWidget);
        expect(find.bySemanticsLabel('Friday'), findsOneWidget);
        expect(find.bySemanticsLabel('Saturday'), findsOneWidget);
        expect(find.bySemanticsLabel('Sunday'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets(
      'the weekday header keeps two-letter labels at 1.0x, where they fit',
      (tester) async {
        useTallScreen(tester);
        final handle = tester.ensureSemantics();

        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: feelingsCatalogJson()),
            FakeReply(200, body: monthlySummaryJson(month: '2026-08')),
          ]),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();

        expect(find.text('MO'), findsOneWidget);
        expect(find.text('SU'), findsOneWidget);
        handle.dispose();
      },
    );
  });
}
