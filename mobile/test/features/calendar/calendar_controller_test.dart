import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/calendar/calendar_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

void main() {
  final fixedNow = DateTime(2026, 8, 15);
  final fixedMonth = const YearMonth(2026, 8);

  ProviderContainer buildContainer(Harness harness) {
    final container = ProviderContainer(
      overrides: [
        ...harness.baseOverrides,
        calendarNowProvider.overrideWithValue(fixedNow),
      ],
      retry: Harness.noRetry,
    );
    addTearDown(container.dispose);
    return container;
  }

  Harness configuredHarness(FakeHttpAdapter adapter) => Harness(
    settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
    adapter: adapter,
  );

  /// Builds a container and lets the initial (deferred) load run to
  /// completion.
  ///
  /// Touching the provider before the first [pumpEventQueue] matters: a
  /// [NotifierProvider] builds lazily on first read, and `build`'s own
  /// deferred load is scheduled only once that first read happens. Reading
  /// it only after a pump would let `build` run *after* the pump returns,
  /// racing whatever the test does next against the notifier's own initial
  /// fetch.
  Future<ProviderContainer> readyContainer(FakeHttpAdapter adapter) async {
    final container = buildContainer(configuredHarness(adapter));
    container.read(calendarControllerProvider);
    await pumpEventQueue();
    return container;
  }

  test(
    'build fetches the current month and gates the spinner on hasLoaded',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: monthlySummaryJson(
            month: '2026-08',
            days: [
              daySummaryJson(date: '2026-08-05', feelings: const ['happy']),
            ],
            averageEntriesPerDay: 0.5,
          ),
        ),
      ]);
      final container = buildContainer(configuredHarness(adapter));

      expect(container.read(calendarControllerProvider).hasLoaded, isFalse);
      await pumpEventQueue();

      final state = container.read(calendarControllerProvider);
      expect(state.hasLoaded, isTrue);
      expect(state.month, fixedMonth);
      expect(state.summary!.days.single.feelings.single.key, 'happy');
      expect(adapter.requests.last.uri.queryParameters['month'], '2026-08');
    },
  );

  test('nextMonth updates the month synchronously and keeps the old summary while it loads', () async {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsCatalogJson()),
      FakeReply(200, body: monthlySummaryJson(month: '2026-08')),
      FakeReply(200, body: monthlySummaryJson(month: '2026-09')),
    ]);
    final container = await readyContainer(adapter);
    final firstSummary = container.read(calendarControllerProvider).summary;

    container.read(calendarControllerProvider.notifier).nextMonth();

    // The month label updates before the new request even lands.
    expect(
      container.read(calendarControllerProvider).month,
      const YearMonth(2026, 9),
    );
    expect(
      container.read(calendarControllerProvider).summary,
      same(firstSummary),
    );

    await pumpEventQueue();
    expect(
      container.read(calendarControllerProvider).month,
      const YearMonth(2026, 9),
    );
    expect(adapter.requests.last.uri.queryParameters['month'], '2026-09');
  });

  test('previousMonth moves back a month', () async {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsCatalogJson()),
      FakeReply(200, body: monthlySummaryJson(month: '2026-08')),
      FakeReply(200, body: monthlySummaryJson(month: '2026-07')),
    ]);
    final container = await readyContainer(adapter);

    container.read(calendarControllerProvider.notifier).previousMonth();
    await pumpEventQueue();

    expect(
      container.read(calendarControllerProvider).month,
      const YearMonth(2026, 7),
    );
  });

  test(
    'a failed fetch still marks hasLoaded and records the message',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(500, body: {'error': 'boom'}),
      ]);
      final container = await readyContainer(adapter);

      final state = container.read(calendarControllerProvider);
      expect(state.hasLoaded, isTrue);
      expect(state.summary, isNull);
      expect(state.errorMessage, isNotNull);
    },
  );

  test(
    'dismissError clears the message without touching anything else',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(500, body: {'error': 'boom'}),
      ]);
      final container = await readyContainer(adapter);

      container.read(calendarControllerProvider.notifier).dismissError();

      expect(container.read(calendarControllerProvider).errorMessage, isNull);
    },
  );

  test(
    'reloadCurrentMonth re-fetches whichever month is on screen, even after navigating away '
    'from the month the screen first opened on',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(200, body: monthlySummaryJson(month: '2026-08')),
        FakeReply(200, body: monthlySummaryJson(month: '2026-09')),
        FakeReply(200, body: monthlySummaryJson(month: '2026-09')),
      ]);
      final container = await readyContainer(adapter);
      container.read(calendarControllerProvider.notifier).nextMonth();
      await pumpEventQueue();
      final requestsBefore = adapter.requests.length;

      await container
          .read(calendarControllerProvider.notifier)
          .reloadCurrentMonth();

      expect(adapter.requests.length, requestsBefore + 1);
      expect(adapter.requests.last.uri.queryParameters['month'], '2026-09');
    },
  );
}
