import 'package:find_my_patterns/core/diary/diary_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/experiments/experiment_results_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

void main() {
  Harness configuredHarness(FakeHttpAdapter adapter) => Harness(
    settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
    adapter: adapter,
  );

  ProviderContainer buildContainer(Harness harness) {
    final container = harness.container();
    addTearDown(container.dispose);
    return container;
  }

  test('fetches results for the given experiment id', () async {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: experimentResultsJson()),
    ]);
    final container = buildContainer(configuredHarness(adapter));

    final results = await container.read(
      experimentResultsControllerProvider('experiment-1').future,
    );

    expect(results.experiment.id, 'experiment-1');
    expect(adapter.requests.single.path, '/experiments/experiment-1/results');
  });

  test('refresh refetches', () async {
    final adapter = FakeHttpAdapter([
      FakeReply(
        200,
        body: experimentResultsJson(
          experiment: experimentJson(status: 'active'),
        ),
      ),
      FakeReply(
        200,
        body: experimentResultsJson(
          experiment: experimentJson(status: 'finished'),
        ),
      ),
    ]);
    final container = buildContainer(configuredHarness(adapter));
    final first = await container.read(
      experimentResultsControllerProvider('experiment-1').future,
    );
    expect(first.experiment.status.name, 'active');

    await container
        .read(experimentResultsControllerProvider('experiment-1').notifier)
        .refresh();

    final second = container
        .read(experimentResultsControllerProvider('experiment-1'))
        .value;
    expect(second?.experiment.status.name, 'finished');
  });

  test(
    'abandon posts to /experiments/{id}/abandon, bumps the diary write '
    'signal, then refetches',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(
          200,
          body: experimentResultsJson(
            experiment: experimentJson(status: 'active'),
          ),
        ),
        FakeReply(200, body: experimentJson(status: 'abandoned')),
        FakeReply(
          200,
          body: experimentResultsJson(
            experiment: experimentJson(status: 'abandoned'),
          ),
        ),
      ]);
      final container = buildContainer(configuredHarness(adapter));
      await container.read(
        experimentResultsControllerProvider('experiment-1').future,
      );
      final signalBefore = container.read(diaryWriteSignalProvider);

      await container
          .read(experimentResultsControllerProvider('experiment-1').notifier)
          .abandon();

      expect(adapter.requests[1].method, 'POST');
      expect(adapter.requests[1].path, '/experiments/experiment-1/abandon');
      expect(container.read(diaryWriteSignalProvider), signalBefore + 1);
      final state = container
          .read(experimentResultsControllerProvider('experiment-1'))
          .value;
      expect(state?.experiment.status.name, 'abandoned');
    },
  );
}
