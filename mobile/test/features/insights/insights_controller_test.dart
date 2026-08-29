import 'package:find_my_patterns/core/network/api_error.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/insights/insights_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import '../experiments/json_fixtures.dart'
    show experimentJson, noActiveExperimentErrorJson;
import 'json_fixtures.dart';

void main() {
  /// Wires a [Harness] into a headless [ProviderContainer] -- no widget tree
  /// needed for testing the controller's own fetch/refresh logic.
  ProviderContainer buildContainer(Harness harness) {
    final container = harness.container();
    addTearDown(container.dispose);
    return container;
  }

  /// `GET /experiments/active`'s reply when nothing is running -- the
  /// common case every test in this file that does not care about R-3b
  /// scripts once per `InsightsController._fetch()` cycle, right after its
  /// own `whenInsightsJson()` reply.
  FakeReply noActiveExperimentReply() =>
      FakeReply(404, body: noActiveExperimentErrorJson());

  Harness configuredHarness(FakeHttpAdapter adapter) => Harness(
    settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
    adapter: adapter,
  );

  test(
    'loads the patterns, withdrawals, constants and when-panel together',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: insightsResultJson(
            patterns: [patternJson()],
            withdrawals: [withdrawalJson()],
            newWithdrawalCount: 1,
          ),
        ),
        FakeReply(200, body: whenInsightsJson()),
        noActiveExperimentReply(),
      ]);
      final container = buildContainer(configuredHarness(adapter));

      final state = await container.read(insightsControllerProvider.future);

      expect(state.patterns, hasLength(1));
      expect(state.withdrawals, hasLength(1));
      expect(state.newWithdrawalCount, 1);
      expect(state.constants.recencyWindowDays, 30);
      expect(state.whenInsights, isNotNull);
      expect(state.whenInsights!.totalEntries, 12);
    },
  );

  test('splits active and historical patterns by status', () async {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsCatalogJson()),
      FakeReply(
        200,
        body: insightsResultJson(
          patterns: [
            patternJson(id: 'active-1', status: 'active'),
            patternJson(id: 'historical-1', status: 'historical'),
          ],
        ),
      ),
      FakeReply(200, body: whenInsightsJson()),
      noActiveExperimentReply(),
    ]);
    final container = buildContainer(configuredHarness(adapter));

    final state = await container.read(insightsControllerProvider.future);

    expect(state.active.map((p) => p.id), ['active-1']);
    expect(state.historical.map((p) => p.id), ['historical-1']);
  });

  test('carries the active experiment through, when one is running', () async {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsCatalogJson()),
      FakeReply(200, body: insightsResultJson()),
      FakeReply(200, body: whenInsightsJson()),
      FakeReply(200, body: experimentJson()),
    ]);
    final container = buildContainer(configuredHarness(adapter));

    final state = await container.read(insightsControllerProvider.future);

    expect(state.activeExperiment, isNotNull);
    expect(state.activeExperiment!.patternTopic, 'exercise');
  });

  test(
    'a failed "when" fetch leaves the panel absent without failing the page',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(200, body: insightsResultJson(patterns: [patternJson()])),
        FakeReply(500, body: {'error': 'boom'}),
      ]);
      final container = buildContainer(configuredHarness(adapter));

      final state = await container.read(insightsControllerProvider.future);

      expect(state.patterns, hasLength(1));
      expect(state.whenInsights, isNull);
    },
  );

  test(
    'a failed patterns fetch surfaces as an error with no data yet',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(500, body: {'error': 'boom'}),
      ]);
      final container = buildContainer(configuredHarness(adapter));

      await expectLater(
        container.read(insightsControllerProvider.future),
        throwsA(isA<ApiError>()),
      );
      final asyncState = container.read(insightsControllerProvider);
      expect(asyncState.hasError, isTrue);
      expect(asyncState.hasValue, isFalse);
    },
  );

  test(
    'refresh keeps the previous content on screen when the new fetch fails',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(200, body: insightsResultJson(patterns: [patternJson()])),
        FakeReply(200, body: whenInsightsJson()),
        noActiveExperimentReply(),
        FakeReply(500, body: {'error': 'boom'}),
      ]);
      final container = buildContainer(configuredHarness(adapter));
      await container.read(insightsControllerProvider.future);

      await container.read(insightsControllerProvider.notifier).refresh();

      final asyncState = container.read(insightsControllerProvider);
      expect(asyncState.hasError, isTrue);
      // The stale patterns are still there for the screen to render under the
      // error snack bar -- a refresh must never blank a screen the user is
      // already reading.
      expect(asyncState.value?.patterns, hasLength(1));
    },
  );

  test(
    'refresh replaces the content once a subsequent fetch succeeds',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: insightsResultJson(patterns: [patternJson(id: 'first')]),
        ),
        FakeReply(200, body: whenInsightsJson()),
        noActiveExperimentReply(),
        FakeReply(
          200,
          body: insightsResultJson(patterns: [patternJson(id: 'second')]),
        ),
        FakeReply(200, body: whenInsightsJson()),
        noActiveExperimentReply(),
      ]);
      final container = buildContainer(configuredHarness(adapter));
      await container.read(insightsControllerProvider.future);

      await container.read(insightsControllerProvider.notifier).refresh();

      final state = container.read(insightsControllerProvider).value;
      expect(state?.patterns.single.id, 'second');
      // The feeling catalog is cached after its first fetch, so a refresh
      // hits only `/insights`, `/insights/when` and `/experiments/active`,
      // not `/feelings` again.
      expect(adapter.requests, hasLength(7));
    },
  );

  test('acknowledging withdrawals posts to the acknowledge endpoint, then refetches', () async {
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
      FakeReply(200),
      FakeReply(200, body: insightsResultJson(newWithdrawalCount: 0)),
      FakeReply(200, body: whenInsightsJson()),
      noActiveExperimentReply(),
    ]);
    final container = buildContainer(configuredHarness(adapter));
    await container.read(insightsControllerProvider.future);

    await container
        .read(insightsControllerProvider.notifier)
        .acknowledgeWithdrawals();

    expect(adapter.requests[4].method, 'POST');
    expect(adapter.requests[4].path, '/insights/withdrawals/acknowledge');
    final state = container.read(insightsControllerProvider).value;
    expect(state?.newWithdrawalCount, 0);
  });
}
