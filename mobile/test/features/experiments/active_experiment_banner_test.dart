import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/experiment.dart';
import 'package:find_my_patterns/features/experiments/active_experiment_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  Widget app(
    Experiment experiment, {
    CalendarDate? today,
    VoidCallback? onTap,
  }) => MaterialApp(
    home: Scaffold(
      body: ActiveExperimentBanner(
        experiment: experiment,
        today: today ?? const CalendarDate(2026, 8, 3),
        onTap: onTap ?? () {},
      ),
    ),
  );

  testWidgets(
    'reads "more <topic> · day N of length" for a moreOf hypothesis',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          buildExperiment(
            patternTopic: 'walking',
            hypothesisKind: HypothesisKind.moreOf,
            startDate: const CalendarDate(2026, 8, 1),
            endDate: const CalendarDate(2026, 8, 7),
          ),
          today: const CalendarDate(2026, 8, 3),
        ),
      );

      expect(
        find.text('Experiment: more walking · day 3 of 7'),
        findsOneWidget,
      );
    },
  );

  testWidgets('reads "less <topic>" for a lessOf hypothesis', (tester) async {
    await tester.pumpWidget(
      app(
        buildExperiment(
          patternTopic: 'coffee',
          hypothesisKind: HypothesisKind.lessOf,
        ),
      ),
    );

    expect(find.textContaining('Experiment: less coffee'), findsOneWidget);
  });

  testWidgets('tapping the banner calls onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      app(buildExperiment(), onTap: () => tapped = true),
    );

    await tester.tap(find.byType(ActiveExperimentBanner));

    expect(tapped, isTrue);
  });

  testWidgets('the day count clamps to 1 before the experiment has started', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        buildExperiment(
          startDate: const CalendarDate(2026, 8, 10),
          endDate: const CalendarDate(2026, 8, 16),
        ),
        today: const CalendarDate(2026, 8, 3),
      ),
    );

    expect(find.textContaining('day 1 of 7'), findsOneWidget);
  });
}
