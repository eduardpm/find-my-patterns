import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/features/insights/weak_signal_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  Widget app(Pattern pattern, {void Function(String, CalendarDate)? onOpen}) =>
      MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeakSignalRow(
              pattern: pattern,
              constants: buildConstants(),
              onOpenEntry: onOpen ?? (_, _) {},
            ),
          ),
        ),
      );

  testWidgets(
    'shows a one-line caption naming the topic, the feeling and the fixed '
    'reason, and hides the full card until tapped',
    (tester) async {
      await tester.pumpWidget(
        app(
          buildPattern(
            topic: 'work',
            feeling: buildFeeling(label: 'Anxious'),
            direction: PatternDirection.none,
            lift: null,
            narrativeText: 'Work shows up with feeling anxious sometimes.',
          ),
        ),
      );

      expect(
        find.text('work → anxious · not enough contrast yet'),
        findsOneWidget,
      );
      expect(
        find.text('Work shows up with feeling anxious sometimes.'),
        findsNothing,
      );
    },
  );

  testWidgets('prefixes "without" for an inverse pattern, matching the full '
      'card\'s own label', (tester) async {
    await tester.pumpWidget(
      app(
        buildPattern(
          kind: PatternKind.inverse,
          topic: 'screen time',
          feeling: buildFeeling(label: 'Content'),
          direction: PatternDirection.none,
          lift: null,
        ),
      ),
    );

    expect(
      find.text('without screen time → content · not enough contrast yet'),
      findsOneWidget,
    );
  });

  testWidgets('falls back to a generic phrase when the feeling could not be '
      'resolved from the catalog', (tester) async {
    final pattern = buildPattern(
      topic: 'work',
      direction: PatternDirection.none,
      lift: null,
    );
    final withoutFeeling = Pattern(
      pattern.id,
      pattern.kind,
      pattern.topic,
      null,
      pattern.occurrenceCount,
      pattern.lifetimeCount,
      pattern.status,
      pattern.direction,
      pattern.narrativeText,
      pattern.suggestionText,
      pattern.presentCount,
      pattern.presentTotal,
      pattern.absentCount,
      pattern.absentTotal,
      pattern.presentRate,
      pattern.absentRate,
      pattern.baseRate,
      pattern.lift,
      pattern.comparisonReason,
      pattern.comparisonNote,
      pattern.isStrong,
      pattern.lastOccurrenceDate,
      pattern.daysSinceLastOccurrence,
      pattern.historicalNote,
      pattern.confounders,
      pattern.evidence,
      pattern.lastUpdatedAt,
      pattern.recommendation,
    );

    await tester.pumpWidget(app(withoutFeeling));

    expect(
      find.text('work → a feeling · not enough contrast yet'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the row expands it into the full pattern card', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        buildPattern(
          topic: 'work',
          direction: PatternDirection.none,
          lift: null,
          narrativeText: 'Work shows up with feeling anxious sometimes.',
        ),
      ),
    );

    await tester.tap(
      find.text('work → stressed · not enough contrast yet'),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('work → stressed · not enough contrast yet'),
      findsNothing,
    );
    expect(
      find.text('Work shows up with feeling anxious sometimes.'),
      findsOneWidget,
    );
  });

  testWidgets('forwards onOpenEntry through to the expanded card', (
    tester,
  ) async {
    String? openedId;
    CalendarDate? openedDate;
    await tester.pumpWidget(
      app(
        buildPattern(
          topic: 'work',
          direction: PatternDirection.none,
          lift: null,
          evidence: [
            buildEvidence(
              entryId: 'entry-7',
              entryDate: const CalendarDate(2026, 8, 21),
            ),
          ],
        ),
        onOpen: (id, date) {
          openedId = id;
          openedDate = date;
        },
      ),
    );

    await tester.tap(find.text('work → stressed · not enough contrast yet'));
    await tester.pumpAndSettle();
    // "1 entry" (singular, #150) not "1 entries".
    await tester.tap(find.text('1 entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));

    expect(openedId, 'entry-7');
    expect(openedDate, const CalendarDate(2026, 8, 21));
  });
}
