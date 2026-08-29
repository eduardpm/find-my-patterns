import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/monthly_summary.dart';
import 'package:find_my_patterns/features/today/day_summary_card.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

void main() {
  const date = CalendarDate(2026, 8, 28);
  const grateful = Feeling(
    'grateful',
    'Grateful',
    Valence.positive,
    'uplifted',
  );
  const anxious = Feeling('anxious', 'Anxious', Valence.negative, 'tense');

  Entry entryAt(String id, DateTime createdAt, List<Feeling> feelings) => Entry(
    id,
    createdAt,
    date,
    EntryMode.freeform,
    'something happened',
    feelings.isEmpty ? null : feelings.first,
    feelings,
    FeelingSource.confirmed,
    null,
    const {},
    const [],
    null,
    const [],
    1,
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    required List<Entry> entries,
    DaySummary? summary,
    bool isToday = true,
  }) async {
    await tester.pumpWidget(
      Harness().wrap(
        DaySummaryCard(entries: entries, summary: summary, isToday: isToday),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the strongest rating', () {
    testWidgets('is shown when the backend recorded one', (tester) async {
      await pumpCard(
        tester,
        entries: [
          entryAt('a', DateTime.utc(2026, 8, 28, 9), [grateful]),
        ],
        summary: const DaySummary(date, [grateful], intensity: 4),
      );

      expect(find.textContaining('4 of'), findsOneWidget);
    });

    testWidgets(
      'is absent when nothing was rated, rather than showing a zero',
      (
        tester,
      ) async {
        // A day nobody used the dial on must look exactly as it did before the
        // dial existed — an unrated day is not a quiet one.
        await pumpCard(
          tester,
          entries: [
            entryAt('a', DateTime.utc(2026, 8, 28, 9), [grateful]),
          ],
          summary: const DaySummary(date, [grateful]),
        );

        expect(find.text('Strongest'), findsNothing);
        expect(find.textContaining(' of 5'), findsNothing);
      },
    );
  });

  group('what the card counts', () {
    testWidgets('reads the day’s feelings from the backend roll-up', (
      tester,
    ) async {
      // The entry on screen says one thing and the roll-up says another; the
      // roll-up wins, because it is the same number the calendar reports.
      await pumpCard(
        tester,
        entries: [
          entryAt('a', DateTime.utc(2026, 8, 28, 9), [grateful]),
        ],
        summary: const DaySummary(date, [anxious]),
      );

      expect(find.text('Anxious'), findsOneWidget);
      expect(find.text('Grateful'), findsNothing);
    });

    testWidgets('falls back to the entries when no roll-up has arrived', (
      tester,
    ) async {
      await pumpCard(
        tester,
        entries: [
          entryAt('a', DateTime.utc(2026, 8, 28, 9), [grateful]),
        ],
      );

      expect(find.text('Grateful'), findsOneWidget);
    });

    testWidgets('says "1 entry", not "1 entries"', (tester) async {
      await pumpCard(
        tester,
        entries: [
          entryAt('a', DateTime.utc(2026, 8, 28, 9), [grateful]),
        ],
      );

      expect(find.text('entry'), findsOneWidget);
    });

    testWidgets('counts several entries', (tester) async {
      await pumpCard(
        tester,
        entries: [
          entryAt('a', DateTime.utc(2026, 8, 28, 9), [grateful]),
          entryAt('b', DateTime.utc(2026, 8, 28, 21), [anxious]),
        ],
      );

      expect(find.text('2'), findsOneWidget);
      expect(find.text('entries'), findsOneWidget);
    });
  });
}
