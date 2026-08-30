import 'dart:async';

import 'package:find_my_patterns/core/auth/tier.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/diary_providers.dart';
import 'package:find_my_patterns/core/diary/digest.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
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
import '../experiments/json_fixtures.dart'
    show
        experimentJson,
        experimentValidationErrorJson,
        noActiveExperimentErrorJson;
import 'json_fixtures.dart';

/// `GET /experiments/active`'s reply when nothing is running -- the common
/// case every test in this file that is not itself about R-3b scripts once
/// per `InsightsController._fetch()` cycle, right after its own
/// `whenInsightsJson()` reply.
FakeReply noActiveExperimentReply() =>
    FakeReply(404, body: noActiveExperimentErrorJson());

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

  @override
  Future<Digest> digest() => throw UnimplementedError();
}

void main() {
  Harness configuredHarness(
    FakeHttpAdapter adapter, {
    Tier tier = Tier.premium,
  }) => Harness(
    settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
    adapter: adapter,
    tier: tier,
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
    expect(find.text('Coffee'), findsOneWidget);
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

  group('"Worth trying" recommendations (R-1)', () {
    testWidgets('renders above the pattern cards for a qualifying pattern', (
      tester,
    ) async {
      final api = _ControllableInsightsApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [insightsApiProvider.overrideWithValue(api)],
          child: const MaterialApp(home: InsightsScreen()),
        ),
      );
      api.insightsCompleter.complete(
        insightsResultFromFixture(
          patterns: [
            patternFixture(
              id: 'p-exercise',
              topic: 'exercise',
              direction: PatternDirection.keep,
              recommendation: recommendationFixture(
                actionTopic: 'exercise',
                headline: 'More exercise days',
                sentence:
                    'On days without exercise, anxious is 2.7× more '
                    'likely (4 of 6 without vs 1 of 4 with). More '
                    "exercise days may help — here's the evidence.",
                patternRef: 'p-exercise',
              ),
            ),
            // A second qualifying pattern -- proves the section renders more
            // than one card (backend caps at three; this client just renders
            // whatever it is given) and covers the between-cards spacing.
            patternFixture(
              id: 'p-reading',
              topic: 'reading',
              direction: PatternDirection.keep,
              recommendation: recommendationFixture(
                actionTopic: 'reading',
                headline: 'Keep doing reading',
                sentence:
                    'On days with reading, calm is 4.5× more likely '
                    '(3 of 4 with vs 1 of 6 without). Keep doing reading — '
                    "here's the evidence.",
                patternRef: 'p-reading',
              ),
            ),
          ],
        ),
      );
      api.whenCompleter.complete(whenInsightsFromFixture());
      await tester.pumpAndSettle();

      expect(find.text('Worth trying'), findsOneWidget);
      expect(find.text('More exercise days'), findsOneWidget);
      expect(find.text('Keep doing reading'), findsOneWidget);
      // R-0: the sentence renders with its counts intact, exactly as the
      // backend composed it -- never rebuilt from `actionTopic` here.
      expect(
        find.textContaining('4 of 6 without vs 1 of 4 with'),
        findsOneWidget,
      );

      // Above the pattern cards they point at -- the issue's own placement
      // (below withdrawals, above the ranked pattern feed; there are no
      // withdrawals in this fixture).
      final worthTryingY = tester.getTopLeft(find.text('Worth trying')).dy;
      final patternCardY = tester.getTopLeft(find.text('Exercise')).dy;
      expect(worthTryingY, lessThan(patternCardY));
    });

    testWidgets(
      'tapping a card scrolls to and expands its pattern\'s evidence trail',
      (tester) async {
        final api = _ControllableInsightsApi();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [insightsApiProvider.overrideWithValue(api)],
            child: const MaterialApp(home: InsightsScreen()),
          ),
        );
        api.insightsCompleter.complete(
          insightsResultFromFixture(
            patterns: [
              patternFixture(
                id: 'p-exercise',
                topic: 'exercise',
                direction: PatternDirection.keep,
                evidence: [
                  PatternEvidence(
                    'entry-1',
                    const CalendarDate(2026, 8, 18),
                    'Skipped the gym today.',
                    const [],
                    FeelingSource.confirmed,
                  ),
                ],
                recommendation: recommendationFixture(
                  actionTopic: 'exercise',
                  headline: 'More exercise days',
                  patternRef: 'p-exercise',
                ),
              ),
            ],
          ),
        );
        api.whenCompleter.complete(whenInsightsFromFixture());
        await tester.pumpAndSettle();

        // Collapsed on first paint -- the trail is not shown until asked
        // for, from either the card's own footer or this section.
        expect(find.text('Skipped the gym today.'), findsNothing);

        await tester.tap(find.text('More exercise days'));
        await tester.pumpAndSettle();

        // Expanded in place on the pattern's own card -- never a new
        // route (`PatternCardState.expandEvidence`'s doc comment).
        expect(find.text('Skipped the gym today.'), findsOneWidget);
        expect(find.text('Hide entries'), findsOneWidget);
      },
    );

    testWidgets('is absent when no pattern qualifies', (tester) async {
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
      expect(find.text('Worth trying'), findsNothing);
    });
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
      noActiveExperimentReply(),
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
    'withdrawals render above the pattern cards, and the "when" panel below '
    'them',
    (tester) async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: insightsResultJson(
            patterns: [patternJson(id: 'active-1', topic: 'planning')],
            withdrawals: [withdrawalJson()],
            newWithdrawalCount: 1,
          ),
        ),
        FakeReply(200, body: whenInsightsJson()),
        noActiveExperimentReply(),
        FakeReply(200, body: seriesJson()),
      ]);
      await tester.pumpWidget(
        configuredHarness(adapter).wrap(const InsightsScreen()),
      );
      await tester.pumpAndSettle();

      final withdrawalsY = tester
          .getTopLeft(find.text('Recently withdrawn'))
          .dy;
      final patternY = tester.getTopLeft(find.text('Planning')).dy;
      final whenY = tester.getTopLeft(find.text('When it happens')).dy;

      expect(withdrawalsY, lessThan(patternY));
      expect(patternY, lessThan(whenY));
    },
  );

  testWidgets(
    'confirmed-lift patterns render as full cards, ranked richest first, '
    'and weak/undefined-lift ones collapse under "Weaker signals"',
    (tester) async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: insightsResultJson(
            patterns: [
              patternJson(
                id: 'weak-1',
                topic: 'screen time',
                direction: 'none',
                lift: null,
              ),
              patternJson(
                id: 'low-1',
                topic: 'sleep',
                direction: 'keep',
                lift: 1.6,
              ),
              patternJson(
                id: 'high-1',
                topic: 'coffee',
                direction: 'change',
                lift: 4.0,
              ),
            ],
          ),
        ),
        FakeReply(200, body: whenInsightsJson()),
        noActiveExperimentReply(),
        FakeReply(200, body: seriesJson()),
      ]);
      await tester.pumpWidget(
        configuredHarness(adapter).wrap(const InsightsScreen()),
      );
      await tester.pumpAndSettle();

      final coffeeY = tester.getTopLeft(find.text('Coffee')).dy;
      final sleepY = tester.getTopLeft(find.text('Sleep')).dy;
      final weakerSignalsY = tester.getTopLeft(find.text('Weaker signals')).dy;
      final weakRowY = tester
          .getTopLeft(
            find.text('screen time → stressed · not enough contrast yet'),
          )
          .dy;

      // The higher-lift confirmed card comes before the lower-lift one,
      // and both confirmed cards come before the collapsed weak tier.
      expect(coffeeY, lessThan(sleepY));
      expect(sleepY, lessThan(weakerSignalsY));
      expect(weakerSignalsY, lessThan(weakRowY));
      // The weak pattern never renders as a full card on first paint --
      // only its collapsed row does, until tapped.
      expect(find.text('Screen time'), findsNothing);
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
      noActiveExperimentReply(),
      // The mood-trend chart's own fetch, request index 4 -- before the
      // "Got it" tap's acknowledge POST, since `_Content` (and the chart at
      // its top) renders as soon as the first load above settles.
      FakeReply(200, body: seriesJson()),
      FakeReply(200),
      FakeReply(200, body: insightsResultJson(newWithdrawalCount: 0)),
      FakeReply(200, body: whenInsightsJson()),
      noActiveExperimentReply(),
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

    expect(adapter.requests[5].method, 'POST');
    expect(adapter.requests[5].path, '/insights/withdrawals/acknowledge');
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
        noActiveExperimentReply(),
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
      // viewport. "1 entry" (singular, #150) not "1 entries".
      await tester.ensureVisible(find.text('1 entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 entry'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));

      expect(openedId, 'entry-9');
      expect(openedDate, const CalendarDate(2026, 8, 19));
    },
  );

  group('R-3b "Test this pattern"', () {
    Future<void> pumpWithOnePattern(
      WidgetTester tester, {
      List<FakeReply> extraReplies = const [],
    }) async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: insightsResultJson(
            patterns: [patternJson(topic: 'coffee', direction: 'change')],
          ),
        ),
        FakeReply(200, body: whenInsightsJson()),
        noActiveExperimentReply(),
        FakeReply(200, body: seriesJson()),
        ...extraReplies,
      ]);
      await tester.pumpWidget(
        configuredHarness(adapter).wrap(const InsightsScreen()),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Test this pattern'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens the setup sheet, phrasing the hypothesis from the '
        'pattern', (tester) async {
      await pumpWithOnePattern(tester);

      await tester.tap(find.text('Test this pattern'));
      await tester.pumpAndSettle();

      // Two matches now: the card's own button, still in the tree behind
      // the sheet, and the sheet's title.
      expect(find.text('Test this pattern'), findsNWidgets(2));
      // A `change`-badged pattern is tested by doing less of it.
      expect(find.textContaining('Try less coffee'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets(
      'starting an experiment posts to /experiments and refreshes the page',
      (tester) async {
        await pumpWithOnePattern(
          tester,
          extraReplies: [
            FakeReply(
              201,
              body: experimentJson(
                patternTopic: 'coffee',
                patternFeeling: 'stressed',
              ),
            ),
            // The refresh `onStarted` triggers.
            FakeReply(
              200,
              body: insightsResultJson(
                patterns: [patternJson(topic: 'coffee', direction: 'change')],
              ),
            ),
            FakeReply(200, body: whenInsightsJson()),
            FakeReply(
              200,
              body: experimentJson(
                patternTopic: 'coffee',
                patternFeeling: 'stressed',
              ),
            ),
          ],
        );

        await tester.tap(find.text('Test this pattern'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();

        expect(find.text('Experiment started: coffee.'), findsOneWidget);
        expect(find.textContaining('EXPERIMENT RUNNING'), findsOneWidget);
      },
    );

    testWidgets(
      'a 422 rejection from the backend is shown verbatim, not reworded',
      (tester) async {
        await pumpWithOnePattern(
          tester,
          extraReplies: [
            FakeReply(
              422,
              body: experimentValidationErrorJson(
                message: '"coffee" is not a currently qualifying pattern.',
              ),
            ),
          ],
        );

        await tester.tap(find.text('Test this pattern'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();

        expect(
          find.text('"coffee" is not a currently qualifying pattern.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a free account sees the Upgrade prompt instead, on the pattern card '
      'itself (M-3, #48)',
      (tester) async {
        final adapter = FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          FakeReply(
            200,
            body: insightsResultJson(
              patterns: [patternJson(topic: 'coffee', direction: 'change')],
            ),
          ),
          FakeReply(200, body: whenInsightsJson()),
          noActiveExperimentReply(),
          FakeReply(200, body: seriesJson()),
        ]);
        await tester.pumpWidget(
          configuredHarness(adapter, tier: Tier.free).wrap(
            const InsightsScreen(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Experiments — Premium'));
        await tester.pumpAndSettle();

        expect(find.text('Test this pattern'), findsNothing);
        expect(find.text('Experiments — Premium'), findsOneWidget);
      },
    );
  });

  testWidgets('a refresh failure surfaces a snack bar without losing the '
      'content underneath', (tester) async {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsCatalogJson()),
      FakeReply(200, body: insightsResultJson(patterns: [patternJson()])),
      FakeReply(200, body: whenInsightsJson()),
      noActiveExperimentReply(),
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
      noActiveExperimentReply(),
      // The mood-trend chart's own fetch, made once for the life of this
      // screen -- app-resume refetches `InsightsController`'s own data, not
      // the chart's, so this reply is not repeated below.
      FakeReply(200, body: seriesJson()),
      FakeReply(200, body: insightsResultJson(patterns: [patternJson()])),
      FakeReply(200, body: whenInsightsJson()),
      noActiveExperimentReply(),
    ]);
    await tester.pumpWidget(
      configuredHarness(adapter).wrap(const InsightsScreen()),
    );
    await tester.pumpAndSettle();
    expect(adapter.requests, hasLength(5));

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();

    expect(adapter.requests, hasLength(8));
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
        noActiveExperimentReply(),
        // The mood-trend chart's own fetch -- made once, since a tab
        // switch does not unmount the screen and the chart's provider is
        // not invalidated by a revisit.
        FakeReply(200, body: seriesJson()),
        FakeReply(200, body: insightsResultJson(patterns: [patternJson()])),
        FakeReply(200, body: whenInsightsJson()),
        noActiveExperimentReply(),
      ]);
      final harness = configuredHarness(adapter);

      Widget onTab({required bool active}) => harness.wrap(
        TickerMode(enabled: active, child: const InsightsScreen()),
      );

      await tester.pumpWidget(onTab(active: true));
      await tester.pumpAndSettle();
      expect(adapter.requests, hasLength(5));

      // Switching to another tab: no refetch just for going away.
      await tester.pumpWidget(onTab(active: false));
      await tester.pumpAndSettle();
      expect(adapter.requests, hasLength(5));

      // Switching back: this is the revisit that refetches.
      await tester.pumpWidget(onTab(active: true));
      await tester.pumpAndSettle();
      expect(adapter.requests, hasLength(8));
    },
  );
}

/// Domain-object versions of the JSON fixtures, for the [_ControllableInsightsApi]
/// tests that skip HTTP and JSON decoding entirely.
InsightsResult insightsResultFromFixture({List<Pattern> patterns = const []}) =>
    InsightsResult(
      patterns,
      const [],
      0,
      false,
      EngineConstants.placeholder,
      null,
    );

Pattern patternFixture({
  String id = 'pattern-1',
  String topic = 'coffee',
  PatternDirection direction = PatternDirection.change,
  Recommendation? recommendation,
  List<PatternEvidence> evidence = const [],
}) => Pattern(
  id,
  PatternKind.forward,
  topic,
  null,
  4,
  4,
  PatternStatus.active,
  direction,
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
  evidence,
  DateTime.utc(2026, 8, 20),
  recommendation,
);

/// R-1: a "Worth trying" recommendation, with defaults matching
/// [patternFixture]'s own topic so a test can pair the two without
/// restating the topic twice.
Recommendation recommendationFixture({
  String actionTopic = 'coffee',
  String headline = 'Keep doing coffee',
  String sentence =
      'On days with coffee, calm is 2.4× more likely '
      "(4 of 5 with vs 6 of 25 without). Keep doing coffee — here's the "
      'evidence.',
  String patternRef = 'pattern-1',
}) => Recommendation(actionTopic, headline, sentence, patternRef);

WhenInsights whenInsightsFromFixture() => const WhenInsights(
  30,
  3,
  0,
  [],
  [],
  null,
  null,
  null,
  null,
  [],
  null,
  null,
  null,
);
