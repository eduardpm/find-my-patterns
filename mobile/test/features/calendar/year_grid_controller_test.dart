import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/calendar/calendar_controller.dart';
import 'package:find_my_patterns/features/calendar/year_grid_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

void main() {
  final fixedNow = DateTime(2026, 8, 15);

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
  /// completion — see `calendar_controller_test.dart`'s identically-named
  /// helper for why this has to happen before the first read rather than
  /// after a pump.
  Future<ProviderContainer> readyContainer(FakeHttpAdapter adapter) async {
    final container = buildContainer(configuredHarness(adapter));
    container.read(yearGridControllerProvider);
    await pumpEventQueue();
    return container;
  }

  test(
    'build fetches the current year (Jan 1 to Dec 31) and gates the '
    'spinner on hasLoaded',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(
          200,
          body: seriesJson(
            points: [seriesPointJson(date: '2026-08-05', score: 1)],
          ),
        ),
      ]);
      final container = buildContainer(configuredHarness(adapter));

      expect(container.read(yearGridControllerProvider).hasLoaded, isFalse);
      await pumpEventQueue();

      final state = container.read(yearGridControllerProvider);
      expect(state.hasLoaded, isTrue);
      expect(state.year, 2026);
      expect(state.points, hasLength(1));
      expect(adapter.requests.last.uri.path, '/insights/series');
      expect(adapter.requests.last.uri.queryParameters['from'], '2026-01-01');
      expect(adapter.requests.last.uri.queryParameters['to'], '2026-12-31');
      expect(adapter.requests.last.uri.queryParameters['granularity'], 'day');
    },
  );

  test(
    'previousYear updates the year synchronously and keeps the old points '
    'while it loads',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: seriesJson()),
        FakeReply(
          200,
          body: seriesJson(
            points: [seriesPointJson(date: '2025-06-01', score: -1)],
          ),
        ),
      ]);
      final container = await readyContainer(adapter);
      final firstPoints = container.read(yearGridControllerProvider).points;

      container.read(yearGridControllerProvider.notifier).previousYear();

      expect(container.read(yearGridControllerProvider).year, 2025);
      expect(
        container.read(yearGridControllerProvider).points,
        same(firstPoints),
      );

      await pumpEventQueue();
      expect(container.read(yearGridControllerProvider).year, 2025);
      expect(
        adapter.requests.last.uri.queryParameters['from'],
        '2025-01-01',
      );
      expect(container.read(yearGridControllerProvider).points, hasLength(1));
    },
  );

  test(
    'nextYear moves forward a year when not yet at the current year',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: seriesJson()),
        FakeReply(200, body: seriesJson()),
        FakeReply(200, body: seriesJson()),
      ]);
      final container = await readyContainer(adapter);
      container.read(yearGridControllerProvider.notifier).previousYear();
      await pumpEventQueue();
      expect(container.read(yearGridControllerProvider).year, 2025);

      container.read(yearGridControllerProvider.notifier).nextYear();
      await pumpEventQueue();

      expect(container.read(yearGridControllerProvider).year, 2026);
    },
  );

  test(
    'nextYear is a no-op once the switcher is already on the current year '
    '(the forward clamp)',
    () async {
      final adapter = FakeHttpAdapter([FakeReply(200, body: seriesJson())]);
      final container = await readyContainer(adapter);
      final requestsBefore = adapter.requests.length;

      container.read(yearGridControllerProvider.notifier).nextYear();
      await pumpEventQueue();

      expect(container.read(yearGridControllerProvider).year, 2026);
      expect(adapter.requests.length, requestsBefore);
    },
  );

  test(
    'a failed fetch still marks hasLoaded and records the message',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(500, body: {'error': 'boom'}),
      ]);
      final container = await readyContainer(adapter);

      final state = container.read(yearGridControllerProvider);
      expect(state.hasLoaded, isTrue);
      expect(state.points, isEmpty);
      expect(state.errorMessage, isNotNull);
    },
  );

  test(
    'dismissError clears the message without touching anything else',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(500, body: {'error': 'boom'}),
      ]);
      final container = await readyContainer(adapter);

      container.read(yearGridControllerProvider.notifier).dismissError();

      expect(container.read(yearGridControllerProvider).errorMessage, isNull);
    },
  );
}
