import 'dart:async';

import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/diary_providers.dart';
import 'package:find_my_patterns/core/diary/insights_api.dart';
import 'package:find_my_patterns/core/diary/mood_series.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/insights/insights_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

/// A double over [InsightsApi] whose two fetches are held open on
/// [Completer]s the test controls -- the only way to look at the screen
/// while a refresh is genuinely still in flight, since the fake HTTP
/// adapter answers synchronously and never leaves that window open.
///
/// [series] is left permanently pending unless a test completes it: the
/// mood-trend chart it feeds is not what these tests are about, and an
/// unresolved [Future] here just leaves that chart in its loading state
/// rather than affecting anything these tests assert on.
class _ControllableInsightsApi implements InsightsApi {
  Completer<InsightsResult> insightsCompleter = Completer<InsightsResult>();
  Completer<WhenInsights> whenCompleter = Completer<WhenInsights>();
  Completer<MoodSeries> seriesCompleter = Completer<MoodSeries>();
  int insightsCalls = 0;
  int whenCalls = 0;
  int acknowledgeCalls = 0;
  int seriesCalls = 0;

  @override
  Future<InsightsResult> insights() {
    insightsCalls++;
    return insightsCompleter.future;
  }

  @override
  Future<WhenInsights> whenInsights() {
    whenCalls++;
    return whenCompleter.future;
  }

  @override
  Future<void> acknowledgeWithdrawals() async {
    acknowledgeCalls++;
  }

  @override
  Future<MoodSeries> series({
    required CalendarDate from,
    required CalendarDate to,
  }) {
    seriesCalls++;
    return seriesCompleter.future;
  }
}

void main() {
  Harness configuredHarness(FakeHttpAdapter adapter) => Harness(
    settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
    adapter: adapter,
  );

  testWidgets('shows a spinner before the first load, and nothing else yet', (
    tester,
  ) async {
    final api = _ControllableInsightsApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [insightsApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);

    api.insightsCompleter.complete(
      insightsResultFromFixture(patterns: [patternFixture()]),
    );
    api.whenCompleter.complete(whenInsightsFromFixture());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Happening now'), findsOneWidget);
  });

  testWidgets('a refresh keeps existing content on screen instead of flashing '
      'a spinner over it', (tester) async {
    final api = _ControllableInsightsApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [insightsApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );
    api.insightsCompleter.complete(
      insightsResultFromFixture(patterns: [patternFixture(topic: 'coffee')]),
    );
    api.whenCompleter.complete(whenInsightsFromFixture());
    await tester.pumpAndSettle();
    expect(find.text('Coffee'), findsOneWidget);

    // A new refresh cycle -- held open deliberately.
    api.insightsCompleter = Completer<InsightsResult>();
    api.whenCompleter = Completer<WhenInsights>();
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump();

    // The refresh is genuinely stuck mid-flight (never completed above),
    // yet the old content is still there and no spinner has appeared --
    // proof the gate is "has data ever arrived", not "is a fetch running".
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    api.insightsCompleter.complete(
      insightsResultFromFixture(patterns: [patternFixture(topic: 'tea')]),
    );
    api.whenCompleter.complete(whenInsightsFromFixture());
    await tester.pumpAndSettle();
    expect(find.text('Tea'), findsOneWidget);
  });

  testWidgets(
    'a first load that fails with no server configured offers "Open Settings"',
    (tester) async {
      var openedSettings = false;
      await tester.pumpWidget(
        Harness().wrap(
          InsightsScreen(onOpenSettings: () => openedSettings = true),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Set your server address in Settings.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open Settings'));
      expect(openedSettings, isTrue);
    },
  );

  testWidgets('shows the insufficient-data empty state, reading the '
      'thresholds from the response', (tester) async {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsCatalogJson()),
      FakeReply(200, body: insightsResultJson(insufficientData: true)),
      FakeReply(200, body: whenInsightsJson(totalEntries: 0)),
      // The mood-trend chart's own fetch, made once `_Content` (and so the
      // chart at its top) first renders.
      FakeReply(200, body: seriesJson()),
    ]);
    await tester.pumpWidget(
      configuredHarness(adapter).wrap(const InsightsScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not enough data yet'), findsOneWidget);
    expect(
      find.text(
        'Keep logging entries — once a topic and a feeling repeat at '
        'least 3 times in the last 30 days, the pattern shows up here.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'withdrawals render above the pattern sections and the "when" panel',
    (tester) async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: insightsResultJson(
            patterns: [
              patternJson(id: 'active-1', status: 'active'),
              patternJson(id: 'historical-1', status: 'historical'),
            ],
            withdrawals: [withdrawalJson()],
            newWithdrawalCount: 1,
          ),
        ),
        FakeReply(200, body: whenInsightsJson()),
        FakeReply(200, body: seriesJson()),
      ]);
      await tester.pumpWidget(
        configuredHarness(adapter).wrap(const InsightsScreen()),
      );
      await tester.pumpAndSettle();

      final withdrawalsY = tester
          .getTopLeft(find.text('Recently withdrawn'))
          .dy;
      final activeY = tester.getTopLeft(find.text('Happening now')).dy;
      final historicalY = tester.getTopLeft(find.text('No longer recent')).dy;
      final whenY = tester.getTopLeft(find.text('When it happens')).dy;

      expect(withdrawalsY, lessThan(activeY));
      expect(activeY, lessThan(historicalY));
      expect(historicalY, lessThan(whenY));
    },
  );

  testWidgets('acknowledging withdrawals only appears with unseen ones, and '
      'calls through to the controller', (tester) async {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsCatalogJson()),
      FakeReply(
        200,
        body: insightsResultJson(
          withdrawals: [withdrawalJson()],
          newWithdrawalCount: 1,
        ),
      ),
      FakeReply(200, body: whenInsightsJson()),
      // The mood-trend chart's own fetch, request index 3 -- before the
      // "Got it" tap's acknowledge POST, since `_Content` (and the chart at
      // its top) renders as soon as the first load above settles.
      FakeReply(200, body: seriesJson()),
      FakeReply(200),
      FakeReply(200, body: insightsResultJson(newWithdrawalCount: 0)),
      FakeReply(200, body: whenInsightsJson()),
    ]);
    await tester.pumpWidget(
      configuredHarness(adapter).wrap(const InsightsScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Got it'), findsOneWidget);
    // The mood-trend chart above pushes this below the default test
    // viewport -- scroll it into view before tapping, the same way the
    // evidence test below does for its own off-screen "Open" button.
    await tester.ensureVisible(find.text('Got it'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(adapter.requests[4].method, 'POST');
    expect(adapter.requests[4].path, '/insights/withdrawals/acknowledge');
    expect(find.text('Got it'), findsNothing);
  });

  testWidgets(
    'opening an evidence row calls through with the entry id and date',
    (
      tester,
    ) async {
      String? openedId;
      CalendarDate? openedDate;
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: insightsResultJson(
            patterns: [
              patternJson(
                evidence: [
                  {
                    'entry_id': 'entry-9',
                    'entry_date': '2026-08-19',
                    'raw_text': 'Evidence text.',
                    'feeling_keys': <String>['stressed'],
                  },
                ],
              ),
            ],
          ),
        ),
        FakeReply(200, body: whenInsightsJson()),
        FakeReply(200, body: seriesJson()),
      ]);
      await tester.pumpWidget(
        configuredHarness(adapter).wrap(
          InsightsScreen(
            onOpenEntry: (id, date) {
              openedId = id;
              openedDate = date;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The mood-trend chart above pushes this below the default test
      // viewport.
      await tester.ensureVisible(find.text('1 entries'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 entries'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));

      expect(openedId, 'entry-9');
      expect(openedDate, const CalendarDate(2026, 8, 19));
    },
  );

  testWidgets('a refresh failure surfaces a snack bar without losing the '
      'content underneath', (tester) async {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsCatalogJson()),
      FakeReply(200, body: insightsResultJson(patterns: [patternJson()])),
      FakeReply(200, body: whenInsightsJson()),
      // The mood-trend chart's own fetch, consumed by the first load
      // before the resume below issues its own (failing) insights request.
      FakeReply(200, body: seriesJson()),
      FakeReply(500, body: {'error': 'server exploded'}),
    ]);
    await tester.pumpWidget(
      configuredHarness(adapter).wrap(const InsightsScreen()),
    );
    await tester.pumpAndSettle();

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();

    expect(find.text('server exploded'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
  });

  testWidgets('resuming the app refetches', (tester) async {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsCatalogJson()),
      FakeReply(200, body: insightsResultJson(patterns: [patternJson()])),
      FakeReply(200, body: whenInsightsJson()),
      // The mood-trend chart's own fetch, made once for the life of this
      // screen -- app-resume refetches `InsightsController`'s own data, not
      // the chart's, so this reply is not repeated below.
      FakeReply(200, body: seriesJson()),
      FakeReply(200, body: insightsResultJson(patterns: [patternJson()])),
      FakeReply(200, body: whenInsightsJson()),
    ]);
    await tester.pumpWidget(
      configuredHarness(adapter).wrap(const InsightsScreen()),
    );
    await tester.pumpAndSettle();
    expect(adapter.requests, hasLength(4));

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();

    expect(adapter.requests, hasLength(6));
  });

  testWidgets(
    'revisiting the tab refetches, leaving merely tapping away alone',
    (
      tester,
    ) async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(200, body: insightsResultJson(patterns: [patternJson()])),
        FakeReply(200, body: whenInsightsJson()),
        // The mood-trend chart's own fetch -- made once, since a tab
        // switch does not unmount the screen and the chart's provider is
        // not invalidated by a revisit.
        FakeReply(200, body: seriesJson()),
        FakeReply(200, body: insightsResultJson(patterns: [patternJson()])),
        FakeReply(200, body: whenInsightsJson()),
      ]);
      final harness = configuredHarness(adapter);

      Widget onTab({required bool active}) => harness.wrap(
        TickerMode(enabled: active, child: const InsightsScreen()),
      );

      await tester.pumpWidget(onTab(active: true));
      await tester.pumpAndSettle();
      expect(adapter.requests, hasLength(4));

      // Switching to another tab: no refetch just for going away.
      await tester.pumpWidget(onTab(active: false));
      await tester.pumpAndSettle();
      expect(adapter.requests, hasLength(4));

      // Switching back: this is the revisit that refetches.
      await tester.pumpWidget(onTab(active: true));
      await tester.pumpAndSettle();
      expect(adapter.requests, hasLength(6));
    },
  );
}

/// Domain-object versions of the JSON fixtures, for the [_ControllableInsightsApi]
/// tests that skip HTTP and JSON decoding entirely.
InsightsResult insightsResultFromFixture({List<Pattern> patterns = const []}) =>
    InsightsResult(patterns, const [], 0, false, EngineConstants.placeholder);

Pattern patternFixture({String topic = 'coffee'}) => Pattern(
  'pattern-1',
  PatternKind.forward,
  topic,
  null,
  4,
  4,
  PatternStatus.active,
  PatternDirection.change,
  'A narrative.',
  'A suggestion.',
  4,
  5,
  6,
  25,
  0.8,
  0.24,
  0.33,
  2.4,
  null,
  null,
  false,
  null,
  null,
  null,
  const [],
  const [],
  DateTime.utc(2026, 8, 20),
);

WhenInsights whenInsightsFromFixture() =>
    const WhenInsights(30, 3, 0, [], [], null, null, null, null);
