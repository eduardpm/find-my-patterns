import 'package:find_my_patterns/core/diary/experiment.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/experiments/experiment_setup_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import '../insights/fixtures.dart' show buildFeeling, buildPattern;
import 'fixtures.dart';
import 'json_fixtures.dart';

void main() {
  Pattern changePattern({String topic = 'coffee'}) => buildPattern(
    topic: topic,
    direction: PatternDirection.change,
    feeling: buildFeeling(key: 'stressed', label: 'Stressed'),
  );

  Pattern keepPattern({String topic = 'walking'}) => buildPattern(
    topic: topic,
    direction: PatternDirection.keep,
    feeling: buildFeeling(key: 'happy', label: 'Happy'),
  );

  Widget app({
    required Pattern pattern,
    Experiment? activeExperiment,
    ValueChanged<Experiment>? onStarted,
    FakeHttpAdapter? adapter,
  }) {
    final harness = Harness(
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
      adapter: adapter,
    );
    return harness.wrap(
      ExperimentSetupSheet(
        pattern: pattern,
        constants: buildExperimentConstants(),
        activeExperiment: activeExperiment,
        onStarted: onStarted ?? (_) {},
      ),
    );
  }

  testWidgets('phrases the hypothesis as "less" for a change-badged pattern', (
    tester,
  ) async {
    await tester.pumpWidget(app(pattern: changePattern(topic: 'coffee')));

    expect(
      find.textContaining(
        'Try less coffee for the next 7 days and see what happens to '
        'stressed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('phrases the hypothesis as "more" for a keep-badged pattern', (
    tester,
  ) async {
    await tester.pumpWidget(app(pattern: keepPattern(topic: 'walking')));

    expect(
      find.textContaining(
        'Try more walking for the next 7 days and see what happens to '
        'happy.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the length stepper is bounded to the given constants', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(pattern: changePattern(), activeExperiment: null),
    );
    // Overrides via a rebuild aren't needed; default constants are 7..28.

    expect(find.text('7 days'), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);

    // Decrementing at the minimum does nothing -- the button is disabled.
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(find.text('7 days'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('8 days'), findsOneWidget);
  });

  testWidgets(
    'starting posts to /experiments with the phrased hypothesis and '
    'chosen length, then calls onStarted',
    (tester) async {
      Experiment? started;
      final adapter = FakeHttpAdapter([
        FakeReply(201, body: experimentJson(patternTopic: 'coffee')),
      ]);

      await tester.pumpWidget(
        app(
          pattern: changePattern(topic: 'coffee'),
          adapter: adapter,
          onStarted: (experiment) => started = experiment,
        ),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(started, isNotNull);
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/experiments');
      expect(request.data, {
        'pattern_topic': 'coffee',
        'pattern_feeling': 'stressed',
        'hypothesis_kind': 'less_of',
        'length_days': 8,
      });
    },
  );

  testWidgets('a 422 rejection shows the backend message verbatim, and the '
      'sheet stays open', (tester) async {
    final adapter = FakeHttpAdapter([
      FakeReply(
        422,
        body: experimentValidationErrorJson(
          message: '"coffee" is not a currently qualifying pattern.',
        ),
      ),
    ]);

    await tester.pumpWidget(app(pattern: changePattern(), adapter: adapter));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(
      find.text('"coffee" is not a currently qualifying pattern.'),
      findsOneWidget,
    );
    expect(find.text('Start'), findsOneWidget);
  });

  group('single-active conflict', () {
    testWidgets(
      'shows the blocking experiment instead of the length picker, and '
      'offers to abandon and start instead',
      (tester) async {
        await tester.pumpWidget(
          app(
            pattern: changePattern(topic: 'coffee'),
            activeExperiment: buildExperiment(patternTopic: 'exercise'),
          ),
        );

        expect(
          find.textContaining('An experiment is already running: exercise'),
          findsOneWidget,
        );
        expect(find.text('7 days'), findsNothing);
        expect(
          find.text('Abandon it and start this instead'),
          findsOneWidget,
        );
      },
    );

    testWidgets('abandons the blocking experiment, then starts this one', (
      tester,
    ) async {
      Experiment? started;
      final adapter = FakeHttpAdapter([
        FakeReply(
          200,
          body: experimentJson(id: 'blocking', status: 'abandoned'),
        ),
        FakeReply(201, body: experimentJson(patternTopic: 'coffee')),
      ]);

      await tester.pumpWidget(
        app(
          pattern: changePattern(topic: 'coffee'),
          activeExperiment: buildExperiment(
            id: 'blocking',
            patternTopic: 'exercise',
          ),
          adapter: adapter,
          onStarted: (experiment) => started = experiment,
        ),
      );

      await tester.tap(find.text('Abandon it and start this instead'));
      await tester.pumpAndSettle();

      expect(started, isNotNull);
      expect(adapter.requests[0].path, '/experiments/blocking/abandon');
      expect(adapter.requests[1].path, '/experiments');
    });
  });
}
