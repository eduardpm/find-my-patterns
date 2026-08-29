import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/diary_providers.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/today/today_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_backdate_nudge_store.dart';
import '../../support/fake_http.dart';
import '../../support/harness.dart';
import '../experiments/json_fixtures.dart'
    show experimentJson, noActiveExperimentErrorJson;
import 'json_fixtures.dart';

void main() {
  // A fixed instant so "today" never depends on the real clock.
  final fixedNow = DateTime.utc(2026, 8, 28, 10);
  final today = CalendarDate.today(now: fixedNow);
  final yesterday = today.addDays(-1);

  /// The feelings catalog fetch every entries/monthly-summary call makes
  /// internally, the first time -- see `EntriesApi`/`MonthlySummaryApi`'s
  /// own shared `FeelingsApi` cache. Always the first request in a fresh
  /// container's lifetime; never repeated after that.
  final feelingsReply = FakeReply(200, body: feelingsCatalogJson());

  /// `GET /experiments/active`'s reply when nothing is running -- the
  /// fourth call `_load` makes while `date == today`, for a test that
  /// scripts the sequence by hand instead of through [loadReplies].
  FakeReply noActiveExperimentReply() =>
      FakeReply(404, body: noActiveExperimentErrorJson());

  ({
    ProviderContainer container,
    TodayController controller,
    FakeHttpAdapter adapter,
    FakeBackdateNudgeStore nudgeStore,
  })
  buildEnv(
    List<FakeReply> replies, {
    DateTime? now,
    FakeBackdateNudgeStore? nudgeStore,
  }) {
    final adapter = FakeHttpAdapter([feelingsReply, ...replies]);
    final harness = Harness(
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
      adapter: adapter,
    );
    final store = nudgeStore ?? FakeBackdateNudgeStore();
    final container = ProviderContainer(
      overrides: [
        requireAuthProvider.overrideWithValue(harness.requireAuth),
        settingsStoreProvider.overrideWithValue(harness.store),
        apiClientProvider.overrideWithValue(harness.client),
        backdateNudgeStoreProvider.overrideWithValue(store),
        todayControllerProvider.overrideWith(
          () => TodayController(
            now: () => now ?? fixedNow,
            delay: (_) async {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(todayControllerProvider.notifier);
    return (
      container: container,
      controller: controller,
      adapter: adapter,
      nudgeStore: store,
    );
  }

  /// One `refresh`'s worth of replies while showing *today*, once the
  /// feelings catalog is already cached: entries, the monthly summary, the
  /// writing-streak series (#40), then the active experiment (R-3b) --
  /// `_loadStreak` and `_loadActiveExperiment` only make their calls while
  /// `date == today`, so this is only the right script for a load that
  /// lands on today. A load of a past day needs [pastDayReplies] instead.
  List<FakeReply> loadReplies({
    List<Map<String, Object?>> entries = const [],
    List<Map<String, Object?>> days = const [],
    List<CalendarDate> streakDays = const [],
    FakeReply? activeExperimentReply,
  }) => [
    FakeReply(200, body: entriesJson(entries)),
    FakeReply(200, body: monthlySummaryJson(days: days)),
    FakeReply(200, body: seriesJson(days: streakDays)),
    activeExperimentReply ?? noActiveExperimentReply(),
  ];

  /// One `refresh`'s worth of replies while showing a day other than today:
  /// entries and the monthly summary only. `_loadStreak` never queries the
  /// series endpoint off today (#40), so there is no third reply to script.
  List<FakeReply> pastDayReplies({
    List<Map<String, Object?>> entries = const [],
    List<Map<String, Object?>> days = const [],
  }) => [
    FakeReply(200, body: entriesJson(entries)),
    FakeReply(200, body: monthlySummaryJson(days: days)),
  ];

  group('build', () {
    test('starts on today, with nothing loaded yet', () {
      final env = buildEnv([]);
      final state = env.container.read(todayControllerProvider);
      expect(state.date, today);
      expect(state.hasLoaded, isFalse);
      expect(state.entries, isEmpty);
    });

    test('canGoForward is false on today', () {
      final env = buildEnv([]);
      expect(env.controller.canGoForward, isFalse);
    });
  });

  group('refresh', () {
    test('loads entries and the day summary, then marks hasLoaded', () async {
      final env = buildEnv(
        loadReplies(
          entries: [entryJson()],
          days: [daySummaryJson(date: today, intensity: 4)],
        ),
      );

      await env.controller.refresh();

      final state = env.container.read(todayControllerProvider);
      expect(state.hasLoaded, isTrue);
      expect(state.isRefreshing, isFalse);
      expect(state.entries, hasLength(1));
      expect(state.daySummary?.intensity, 4);
    });

    test(
      'a failed entries load keeps hasLoaded true and reports the error',
      () async {
        final env = buildEnv([
          FakeReply(500, body: {'error': 'server exploded'}),
          FakeReply(200, body: monthlySummaryJson(days: const [])),
          FakeReply(200, body: seriesJson()),
          noActiveExperimentReply(),
        ]);

        await env.controller.refresh();

        final state = env.container.read(todayControllerProvider);
        expect(state.hasLoaded, isTrue);
        expect(state.errorMessage, 'server exploded');
        expect(state.entries, isEmpty);
      },
    );

    test('a missing day summary is silent -- no error message', () async {
      final env = buildEnv([
        FakeReply(200, body: entriesJson(const [])),
        FakeReply(500, body: {'error': 'boom'}),
        FakeReply(200, body: seriesJson()),
        noActiveExperimentReply(),
      ]);

      await env.controller.refresh();

      final state = env.container.read(todayControllerProvider);
      expect(state.errorMessage, isNull);
      expect(state.daySummary, isNull);
    });

    test('a later failure keeps the entries a prior success already put on '
        'screen', () async {
      final env = buildEnv([
        ...loadReplies(entries: [entryJson()]),
        FakeReply(500, body: {'error': 'boom'}),
        FakeReply(200, body: monthlySummaryJson(days: const [])),
        FakeReply(200, body: seriesJson()),
        noActiveExperimentReply(),
      ]);
      await env.controller.refresh();
      expect(env.container.read(todayControllerProvider).entries, hasLength(1));

      // A second refresh whose entries call fails leaves the prior list on
      // screen rather than blanking it.
      await env.controller.refresh();

      expect(env.container.read(todayControllerProvider).entries, hasLength(1));
      expect(env.container.read(todayControllerProvider).errorMessage, 'boom');
    });
  });

  group('streakDays (#40)', () {
    test('computes the streak from the series call\'s presence days', () async {
      final env = buildEnv(
        loadReplies(streakDays: [today, yesterday, yesterday.addDays(-1)]),
      );

      await env.controller.refresh();

      expect(env.container.read(todayControllerProvider).streakDays, 3);
    });

    test(
      'queries the series endpoint over the full window ending today',
      () async {
        final env = buildEnv(loadReplies());

        await env.controller.refresh();

        final from = today.addDays(-399);
        // Not `.last`: the active-experiment fetch (R-3b) follows the
        // series request in `_load`, so this is the second-to-last one.
        expect(
          env.adapter.requests[env.adapter.requests.length - 2].path,
          '/insights/series?from=$from&to=$today&granularity=day',
        );
      },
    );

    test(
      'is zero, and makes no series request, while showing a past day',
      () async {
        final env = buildEnv([
          ...loadReplies(streakDays: [today, yesterday]),
          ...pastDayReplies(),
        ]);
        await env.controller.refresh();
        expect(env.container.read(todayControllerProvider).streakDays, 2);

        await env.controller.showPreviousDay();

        final state = env.container.read(todayControllerProvider);
        expect(state.streakDays, 0);
        // Exactly seven requests total: feelings, then entries + monthly
        // summary + series + the active experiment for today, then entries
        // + monthly summary for yesterday -- no series or experiment
        // request for the past day.
        expect(env.adapter.requests, hasLength(7));
      },
    );

    test('resets to zero on a failed series request', () async {
      final env = buildEnv([
        FakeReply(200, body: entriesJson(const [])),
        FakeReply(200, body: monthlySummaryJson(days: const [])),
        FakeReply(500, body: {'error': 'boom'}),
        noActiveExperimentReply(),
      ]);

      await env.controller.refresh();

      final state = env.container.read(todayControllerProvider);
      expect(state.streakDays, 0);
      // Silent, like a missing day summary -- no error message for a
      // second unreachable-backend call.
      expect(state.errorMessage, isNull);
    });
  });

  group('totalEntries (#36)', () {
    test(
      'sums entry_count across the same series call streakDays reads',
      () async {
        final env = buildEnv(
          loadReplies(streakDays: [today, yesterday, yesterday.addDays(-1)]),
        );

        await env.controller.refresh();

        // `seriesJson`'s fixture gives each named day `entry_count: 1`, so
        // three days sums to three -- no fourth request beyond the one
        // `streakDays` already reads.
        expect(env.container.read(todayControllerProvider).totalEntries, 3);
      },
    );

    test('is zero while showing a past day, the same as streakDays', () async {
      final env = buildEnv([
        ...loadReplies(streakDays: [today, yesterday]),
        ...pastDayReplies(),
      ]);
      await env.controller.refresh();
      expect(env.container.read(todayControllerProvider).totalEntries, 2);

      await env.controller.showPreviousDay();

      expect(env.container.read(todayControllerProvider).totalEntries, 0);
    });

    test('resets to zero on a failed series request', () async {
      final env = buildEnv([
        FakeReply(200, body: entriesJson(const [])),
        FakeReply(200, body: monthlySummaryJson(days: const [])),
        FakeReply(500, body: {'error': 'boom'}),
        noActiveExperimentReply(),
      ]);

      await env.controller.refresh();

      expect(env.container.read(todayControllerProvider).totalEntries, 0);
    });
  });

  group('activeExperiment (R-3b)', () {
    test(
      'carries the active experiment through, when one is running',
      () async {
        final env = buildEnv(
          loadReplies(
            activeExperimentReply: FakeReply(
              200,
              body: experimentJson(patternTopic: 'exercise'),
            ),
          ),
        );

        await env.controller.refresh();

        final experiment = env.container
            .read(todayControllerProvider)
            .activeExperiment;
        expect(experiment, isNotNull);
        expect(experiment!.patternTopic, 'exercise');
      },
    );

    test('is null while nothing is running', () async {
      final env = buildEnv(loadReplies());

      await env.controller.refresh();

      expect(
        env.container.read(todayControllerProvider).activeExperiment,
        isNull,
      );
    });

    test(
      'is null while showing a past day, and makes no request there',
      () async {
        final env = buildEnv([
          ...loadReplies(
            activeExperimentReply: FakeReply(
              200,
              body: experimentJson(patternTopic: 'exercise'),
            ),
          ),
          ...pastDayReplies(),
        ]);
        await env.controller.refresh();
        expect(
          env.container.read(todayControllerProvider).activeExperiment,
          isNotNull,
        );

        await env.controller.showPreviousDay();

        expect(
          env.container.read(todayControllerProvider).activeExperiment,
          isNull,
        );
      },
    );

    test('is null on a fetch failure, without an error message', () async {
      final env = buildEnv([
        FakeReply(200, body: entriesJson(const [])),
        FakeReply(200, body: monthlySummaryJson(days: const [])),
        FakeReply(200, body: seriesJson()),
        const FakeReply.networkError(),
      ]);

      await env.controller.refresh();

      final state = env.container.read(todayControllerProvider);
      expect(state.activeExperiment, isNull);
      expect(state.errorMessage, isNull);
    });
  });

  group('backdate nudge (#36)', () {
    test('nudgeDismissed defaults true until the store load lands', () {
      final env = buildEnv([]);

      expect(
        env.container.read(todayControllerProvider).nudgeDismissed,
        isTrue,
      );
    });

    test(
      'nudgeDismissed reads false from the store once build\'s load lands',
      () async {
        final env = buildEnv(
          [],
          nudgeStore: FakeBackdateNudgeStore(dismissed: false),
        );

        // build() fires the load as a microtask; nothing else in this test
        // touches the controller, so a single event-loop turn is enough for
        // it to land.
        await Future<void>.delayed(Duration.zero);

        expect(
          env.container.read(todayControllerProvider).nudgeDismissed,
          isFalse,
        );
      },
    );

    test(
      'dismissBackdateNudge flips the state and persists through the store',
      () async {
        final store = FakeBackdateNudgeStore(dismissed: false);
        final env = buildEnv([], nudgeStore: store);
        await Future<void>.delayed(Duration.zero);
        expect(
          env.container.read(todayControllerProvider).nudgeDismissed,
          isFalse,
        );

        await env.controller.dismissBackdateNudge();

        expect(
          env.container.read(todayControllerProvider).nudgeDismissed,
          isTrue,
        );
        expect(store.dismissCount, 1);
        expect(await store.isDismissed(), isTrue);
      },
    );
  });

  group('day navigation', () {
    test('showPreviousDay moves back a day and clears entries first', () async {
      final env = buildEnv([
        ...loadReplies(entries: [entryJson()]),
        ...pastDayReplies(),
      ]);
      await env.controller.refresh();
      expect(env.container.read(todayControllerProvider).entries, hasLength(1));

      final pending = env.controller.showPreviousDay();
      // Cleared synchronously, before the new day's load has resolved.
      expect(env.container.read(todayControllerProvider).entries, isEmpty);
      expect(env.container.read(todayControllerProvider).date, yesterday);
      await pending;

      expect(env.container.read(todayControllerProvider).entries, isEmpty);
    });

    test('showNextDay is clamped at today', () async {
      final env = buildEnv(loadReplies());
      await env.controller.showNextDay();
      expect(env.container.read(todayControllerProvider).date, today);
      expect(env.controller.canGoForward, isFalse);
    });

    test('canGoForward becomes true after stepping back a day, and false '
        'again once back on today', () async {
      final env = buildEnv([...pastDayReplies(), ...loadReplies()]);
      expect(env.controller.canGoForward, isFalse);

      await env.controller.showPreviousDay();
      expect(env.container.read(todayControllerProvider).date, yesterday);
      expect(env.controller.canGoForward, isTrue);

      await env.controller.showNextDay();
      expect(env.container.read(todayControllerProvider).date, today);
      expect(env.controller.canGoForward, isFalse);
    });

    test('showToday returns from a past day to today', () async {
      final env = buildEnv([...pastDayReplies(), ...loadReplies()]);
      await env.controller.showPreviousDay();
      expect(env.container.read(todayControllerProvider).date, yesterday);

      await env.controller.showToday();

      expect(env.container.read(todayControllerProvider).date, today);
      expect(env.controller.isToday, isTrue);
    });
  });

  group('midnight', () {
    test(
      'refresh redirects to the new day when it is following today',
      () async {
        // A clock this test can move forward between refreshes, standing in
        // for the app sitting in the background across midnight.
        var clock = fixedNow;
        final adapter = FakeHttpAdapter([
          feelingsReply,
          ...loadReplies(),
          ...loadReplies(),
        ]);
        final harness = Harness(
          settings: const AppSettings(
            backend: BackendAddress(host: '10.0.2.2'),
          ),
          adapter: adapter,
        );
        final container = ProviderContainer(
          overrides: [
            requireAuthProvider.overrideWithValue(harness.requireAuth),
            settingsStoreProvider.overrideWithValue(harness.store),
            apiClientProvider.overrideWithValue(harness.client),
            backdateNudgeStoreProvider.overrideWithValue(
              FakeBackdateNudgeStore(),
            ),
            todayControllerProvider.overrideWith(
              () => TodayController(now: () => clock, delay: (_) async {}),
            ),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(todayControllerProvider.notifier);
        await controller.refresh();
        expect(container.read(todayControllerProvider).date, today);

        // Midnight passes while the screen sits in the background; the next
        // resume-triggered refresh should notice and follow it forward.
        clock = fixedNow.add(const Duration(days: 1));
        await controller.refresh();

        expect(
          container.read(todayControllerProvider).date,
          CalendarDate.today(now: clock),
        );
      },
    );

    test('a day the reader chose is not swept forward by refresh', () async {
      final env = buildEnv([...pastDayReplies(), ...pastDayReplies()]);
      await env.controller.showPreviousDay();
      expect(env.container.read(todayControllerProvider).date, yesterday);

      await env.controller.refresh();

      // Still parked on yesterday -- refresh must not follow today once
      // the reader has chosen a day.
      expect(env.container.read(todayControllerProvider).date, yesterday);
    });
  });

  group('analysis polling', () {
    test('does not poll when nothing is pending', () async {
      final env = buildEnv(
        loadReplies(entries: [entryJson(analysisPending: false)]),
      );

      await env.controller.refresh();
      await env.controller.analysisSettled;

      // Only the feelings + four requests `refresh` itself made (entries,
      // monthly summary, writing-streak series, active experiment) -- no
      // poll follow-up.
      expect(env.adapter.requests, hasLength(5));
    });

    test('polls while an entry is pending and stops once it settles', () async {
      final env = buildEnv([
        ...loadReplies(entries: [entryJson(analysisPending: true)]),
        FakeReply(200, body: entriesJson([entryJson(analysisPending: false)])),
      ]);

      await env.controller.refresh();
      expect(
        env.container
            .read(todayControllerProvider)
            .entries
            .single
            .analysisPending,
        isTrue,
      );

      await env.controller.analysisSettled;

      expect(
        env.container
            .read(todayControllerProvider)
            .entries
            .single
            .analysisPending,
        isFalse,
      );
    });
  });

  group('diaryWriteSignalProvider', () {
    test(
      'bumping the signal refreshes today with the entry a write just added',
      () async {
        final env = buildEnv([
          ...loadReplies(),
          ...loadReplies(entries: [entryJson()]),
        ]);
        await env.controller.refresh();
        expect(env.container.read(todayControllerProvider).entries, isEmpty);

        env.container.read(diaryWriteSignalProvider.notifier).bump();
        // The listener's refresh is async; let it run to completion. Three
        // sequential requests now hang off one refresh (entries, monthly
        // summary, writing-streak series -- #40's third), one more hop than
        // the default 20 rounds reliably drains alongside the rest of this
        // suite's own pending timers, so this waits longer than the default.
        await pumpEventQueue(times: 100);

        expect(
          env.container.read(todayControllerProvider).entries,
          hasLength(1),
        );
      },
    );

    test(
      'a write while parked on a past day refreshes that day, not today',
      () async {
        final env = buildEnv([
          ...pastDayReplies(),
          ...pastDayReplies(entries: [entryJson()]),
        ]);
        await env.controller.showPreviousDay();
        expect(env.container.read(todayControllerProvider).date, yesterday);

        env.container.read(diaryWriteSignalProvider.notifier).bump();
        await pumpEventQueue();

        final state = env.container.read(todayControllerProvider);
        expect(state.date, yesterday);
        expect(state.entries, hasLength(1));
      },
    );
  });

  group('dismissError', () {
    test('clears the error message', () async {
      final env = buildEnv([
        FakeReply(500, body: {'error': 'boom'}),
        FakeReply(200, body: monthlySummaryJson(days: const [])),
        FakeReply(200, body: seriesJson()),
        noActiveExperimentReply(),
      ]);
      await env.controller.refresh();
      expect(
        env.container.read(todayControllerProvider).errorMessage,
        isNotNull,
      );

      env.controller.dismissError();

      expect(env.container.read(todayControllerProvider).errorMessage, isNull);
    });
  });
}
