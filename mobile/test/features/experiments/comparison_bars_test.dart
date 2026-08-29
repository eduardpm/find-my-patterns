import 'package:find_my_patterns/core/diary/experiment.dart';
import 'package:find_my_patterns/features/experiments/comparison_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  Widget app({
    required ExperimentWindow experimentWindow,
    required ExperimentWindow baselineWindow,
  }) => MaterialApp(
    home: Scaffold(
      body: ComparisonBars(
        experimentWindow: experimentWindow,
        baselineWindow: baselineWindow,
        feelingLabel: 'exhausted',
      ),
    ),
  );

  testWidgets('shows both windows\' percentage and counts', (tester) async {
    await tester.pumpWidget(
      app(
        experimentWindow: buildExperimentWindow(
          presentCount: 1,
          presentTotal: 4,
          presentRate: 0.25,
        ),
        baselineWindow: buildExperimentWindow(
          presentCount: 3,
          presentTotal: 5,
          presentRate: 0.6,
        ),
      ),
    );

    expect(find.text('25%'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('1/4 entries with exhausted'), findsOneWidget);
    expect(find.text('3/5 entries with exhausted'), findsOneWidget);
  });

  testWidgets('a null rate reads as an em dash, never 0%', (tester) async {
    await tester.pumpWidget(
      app(
        experimentWindow: buildExperimentWindow(
          presentCount: 0,
          presentTotal: 0,
          presentRate: null,
        ),
        baselineWindow: buildExperimentWindow(
          presentCount: 2,
          presentTotal: 4,
          presentRate: 0.5,
        ),
      ),
    );

    expect(find.text('—'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('labels "During" and "Before" the experiment', (tester) async {
    await tester.pumpWidget(
      app(
        experimentWindow: buildExperimentWindow(),
        baselineWindow: buildExperimentWindow(),
      ),
    );

    expect(find.text('DURING THE EXPERIMENT'), findsOneWidget);
    expect(find.text('BEFORE THE EXPERIMENT'), findsOneWidget);
  });
}
