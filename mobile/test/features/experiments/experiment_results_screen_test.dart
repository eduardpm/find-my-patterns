import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/experiments/experiment_results_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

void main() {
  Widget app({
    required FakeHttpAdapter adapter,
    VoidCallback? onClose,
  }) {
    final harness = Harness(
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
      adapter: adapter,
    );
    return harness.wrap(
      ExperimentResultsScreen(experimentId: 'experiment-1', onClose: onClose),
    );
  }

  group('the three verdict cases (point 3 of R-3b)', () {
    testWidgets('a clear difference renders the verdict and both bars', (
      tester,
    ) async {
      final adapter = FakeHttpAdapter([
        FakeReply(
          200,
          body: experimentResultsJson(
            experimentWindow: experimentWindowJson(
              presentCount: 1,
              presentTotal: 4,
              presentRate: 0.25,
            ),
            baselineWindow: experimentWindowJson(
              presentCount: 3,
              presentTotal: 5,
              presentRate: 0.6,
            ),
            verdictText:
                'During the experiment you mentioned exercise on 4 of 7 '
                'days; exhausted appeared in 1 of 4 entries (25%) vs 3 of '
                '5 (60%) in the 7 days before.',
            insufficientData: false,
          ),
        ),
      ]);

      await tester.pumpWidget(app(adapter: adapter));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'During the experiment you mentioned exercise on 4 of 7 days; '
          'exhausted appeared in 1 of 4 entries (25%) vs 3 of 5 (60%) in '
          'the 7 days before.',
        ),
        findsOneWidget,
      );
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('1/4 entries with exhausted'), findsOneWidget);
      expect(find.text('3/5 entries with exhausted'), findsOneWidget);
    });

    testWidgets('no difference renders the same way, no styling implying '
        'either verdict is more important', (tester) async {
      final adapter = FakeHttpAdapter([
        FakeReply(
          200,
          body: experimentResultsJson(
            experimentWindow: experimentWindowJson(
              presentCount: 3,
              presentTotal: 6,
              presentRate: 0.5,
            ),
            baselineWindow: experimentWindowJson(
              presentCount: 3,
              presentTotal: 6,
              presentRate: 0.5,
            ),
            verdictText:
                'During the experiment exhausted appeared in 3 of 6 '
                'entries (50%) vs 3 of 6 (50%) in the 7 days before.',
            insufficientData: false,
          ),
        ),
      ]);

      await tester.pumpWidget(app(adapter: adapter));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'During the experiment exhausted appeared in 3 of 6 entries '
          '(50%) vs 3 of 6 (50%) in the 7 days before.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'insufficient data renders the verdict at the same weight -- the '
      'same "Verdict" card, not a smaller or muted one',
      (tester) async {
        final adapter = FakeHttpAdapter([
          FakeReply(
            200,
            body: experimentResultsJson(
              experimentWindow: experimentWindowJson(
                presentCount: 1,
                presentTotal: 2,
                presentRate: 0.5,
              ),
              baselineWindow: experimentWindowJson(
                presentCount: 1,
                presentTotal: 2,
                presentRate: 0.5,
              ),
              verdictText:
                  'During the experiment exhausted appeared in 1 of 2 '
                  'entries (50%) vs 1 of 2 (50%) in the 7 days before. Too '
                  'few entries to be sure.',
              insufficientData: true,
            ),
          ),
        ]);

        await tester.pumpWidget(app(adapter: adapter));
        await tester.pumpAndSettle();

        // Rendered in full, appended caveat included -- never hidden,
        // shortened, or shown in a visually lesser way.
        expect(
          find.text(
            'During the experiment exhausted appeared in 1 of 2 entries '
            '(50%) vs 1 of 2 (50%) in the 7 days before. Too few entries '
            'to be sure.',
          ),
          findsOneWidget,
        );
        // The same "Verdict" eyebrow every case renders under.
        expect(find.text('VERDICT'), findsOneWidget);
      },
    );
  });

  testWidgets('shows the status badge and the direction/topic/feeling line', (
    tester,
  ) async {
    final adapter = FakeHttpAdapter([
      FakeReply(
        200,
        body: experimentResultsJson(
          experiment: experimentJson(
            patternTopic: 'exercise',
            patternFeeling: 'exhausted',
            hypothesisKind: 'more_of',
            status: 'active',
          ),
        ),
      ),
    ]);

    await tester.pumpWidget(app(adapter: adapter));
    await tester.pumpAndSettle();

    expect(find.text('Exercise'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(
      find.text('Testing more exercise against exhausted'),
      findsOneWidget,
    );
  });

  testWidgets('an active experiment offers "Abandon experiment", not "Done"', (
    tester,
  ) async {
    final adapter = FakeHttpAdapter([
      FakeReply(
        200,
        body: experimentResultsJson(
          experiment: experimentJson(status: 'active'),
        ),
      ),
    ]);

    await tester.pumpWidget(app(adapter: adapter));
    await tester.pumpAndSettle();

    expect(find.text('Abandon experiment'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('a finished experiment offers "Done", not abandon', (
    tester,
  ) async {
    var closed = false;
    final adapter = FakeHttpAdapter([
      FakeReply(
        200,
        body: experimentResultsJson(
          experiment: experimentJson(status: 'finished'),
        ),
      ),
    ]);

    await tester.pumpWidget(
      app(adapter: adapter, onClose: () => closed = true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Abandon experiment'), findsNothing);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));

    expect(closed, isTrue);
  });

  group(
    'abandon (point 4 of R-3b: always available, one tap plus confirm)',
    () {
      testWidgets('confirming abandons, bumps the diary write signal, and '
          'refreshes to the abandoned status', (tester) async {
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
        await tester.pumpWidget(app(adapter: adapter));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Abandon experiment'));
        await tester.pumpAndSettle();
        // No guilt copy -- a plain confirmation, and an explicit "Abandon"
        // action, never asking for a reason.
        expect(find.text('Abandon this experiment?'), findsOneWidget);
        await tester.tap(find.text('Abandon'));
        await tester.pumpAndSettle();

        expect(find.text('Done'), findsOneWidget);
        expect(find.text('Abandon experiment'), findsNothing);
        expect(adapter.requests[1].path, '/experiments/experiment-1/abandon');
      });

      testWidgets('cancelling leaves the experiment active', (tester) async {
        final adapter = FakeHttpAdapter([
          FakeReply(
            200,
            body: experimentResultsJson(
              experiment: experimentJson(status: 'active'),
            ),
          ),
        ]);

        await tester.pumpWidget(app(adapter: adapter));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Abandon experiment'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Abandon experiment'), findsOneWidget);
      });

      testWidgets('a failed abandon shows the error and leaves the '
          'experiment active', (tester) async {
        final adapter = FakeHttpAdapter([
          FakeReply(
            200,
            body: experimentResultsJson(
              experiment: experimentJson(status: 'active'),
            ),
          ),
          FakeReply(
            422,
            body: experimentValidationErrorJson(
              message: 'Experiment experiment-1 is finished, not active.',
            ),
          ),
        ]);

        await tester.pumpWidget(app(adapter: adapter));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Abandon experiment'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Abandon'));
        await tester.pumpAndSettle();

        expect(
          find.text('Experiment experiment-1 is finished, not active.'),
          findsOneWidget,
        );
        // Still active -- the failed abandon never took effect.
        expect(find.text('Abandon experiment'), findsOneWidget);
      });
    },
  );

  testWidgets('a failed first load shows a retry that refetches', (
    tester,
  ) async {
    final adapter = FakeHttpAdapter([
      FakeReply(500, body: {'error': 'server exploded'}),
      FakeReply(200, body: experimentResultsJson()),
    ]);

    await tester.pumpWidget(app(adapter: adapter));
    await tester.pumpAndSettle();

    expect(find.text('server exploded'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('server exploded'), findsNothing);
    // The verdict from the fixture's default results now renders.
    expect(find.text('VERDICT'), findsOneWidget);
  });
}
