import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/diary_providers.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/today/today_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
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

  ({
    ProviderContainer container,
    TodayController controller,
    FakeHttpAdapter adapter,
  })
  buildEnv(List<FakeReply> replies, {DateTime? now}) {
    final adapter = FakeHttpAdapter([feelingsReply, ...replies]);
    final harness = Harness(
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
      adapter: adapter,
    );
    final container = ProviderContainer(
      overrides: [
        requireAuthProvider.overrideWithValue(harness.requireAuth),
        settingsStoreProvider.overrideWithValue(harness.store),
        apiClientProvider.overrideWithValue(harness.client),
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
    return (container: container, controller: controller, adapter: adapter);
  }

  /// One `refresh`'s worth of replies once the feelings catalog is already
  /// cached: entries, then the monthly summary.
  List<FakeReply> loadReplies({
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

  group('day navigation', () {
    test('showPreviousDay moves back a day and clears entries first', () async {
      final env = buildEnv([
        ...loadReplies(entries: [entryJson()]),
        ...loadReplies(),
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
      final env = buildEnv([
        ...loadReplies(),
        ...loadReplies(),
        ...loadReplies(),
      ]);
      expect(env.controller.canGoForward, isFalse);

      await env.controller.showPreviousDay();
      expect(env.container.read(todayControllerProvider).date, yesterday);
      expect(env.controller.canGoForward, isTrue);

      await env.controller.showNextDay();
      expect(env.container.read(todayControllerProvider).date, today);
      expect(env.controller.canGoForward, isFalse);
    });

    test('showToday returns from a past day to today', () async {
      final env = buildEnv([...loadReplies(), ...loadReplies()]);
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
      final env = buildEnv([...loadReplies(), ...loadReplies()]);
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

      // Only the feelings + two requests `refresh` itself made -- no poll
      // follow-up.
      expect(env.adapter.requests, hasLength(3));
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
        // The listener's refresh is async; let it run to completion.
        await pumpEventQueue();

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
          ...loadReplies(),
          ...loadReplies(entries: [entryJson()]),
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
