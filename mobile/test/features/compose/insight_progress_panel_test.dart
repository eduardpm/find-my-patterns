import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/features/compose/insight_progress_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  const withPair = InsightProgress(
    7,
    12,
    [ProgressPair('work', 'anxious', 2, 3)],
    0,
    3,
  );

  const withoutPair = InsightProgress(4, 6, [], 0, 3);

  const gated = InsightProgress(
    7,
    12,
    [ProgressPair('work', 'anxious', 2, 3)],
    3,
    3,
  );

  const noTopicsYet = InsightProgress(0, 2, [], 0, 3);

  group('InsightProgressPanel', () {
    testWidgets('shows both lines when there is a near-threshold pair', (
      tester,
    ) async {
      await tester.pumpWidget(host(InsightProgressPanel(progress: withPair)));

      expect(find.text('Tracking 7 topics across 12 entries.'), findsOneWidget);
      expect(
        find.textContaining('Closest to a pattern: '),
        findsOneWidget,
      );
      expect(find.textContaining('work + anxious'), findsOneWidget);
      expect(find.textContaining('2 of 3 occurrences.'), findsOneWidget);
    });

    testWidgets(
      'shows only the tracking line when there is no near-threshold pair',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          host(InsightProgressPanel(progress: withoutPair)),
        );

        expect(
          find.text('Tracking 4 topics across 6 entries.'),
          findsOneWidget,
        );
        expect(find.textContaining('Closest to a pattern'), findsNothing);
      },
    );

    testWidgets(
      'renders nothing once the ≥3 surfaced-patterns gate has tripped',
      (
        tester,
      ) async {
        await tester.pumpWidget(host(InsightProgressPanel(progress: gated)));

        expect(find.byType(InsightProgressPanel), findsOneWidget);
        expect(find.text('Tracking 7 topics across 12 entries.'), findsNothing);
        expect(find.textContaining('Closest to a pattern'), findsNothing);
      },
    );

    testWidgets('renders nothing when no topic has been tracked yet', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(InsightProgressPanel(progress: noTopicsYet)),
      );

      expect(find.byType(InsightProgressPanel), findsOneWidget);
      expect(find.textContaining('Tracking'), findsNothing);
    });

    testWidgets('bolds exactly the topic+feeling span, not the whole line', (
      tester,
    ) async {
      await tester.pumpWidget(host(InsightProgressPanel(progress: withPair)));

      final richText = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.textSpan)
          .whereType<TextSpan>()
          .firstWhere(
            (span) => span.toPlainText().contains('work + anxious'),
          );
      final boldSpan = richText.children!.whereType<TextSpan>().firstWhere(
        (child) => child.text == 'work + anxious',
      );
      expect(boldSpan.style?.fontWeight, FontWeight.w600);
    });
  });
}
