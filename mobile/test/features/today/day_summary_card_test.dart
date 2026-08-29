import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/monthly_summary.dart';
import 'package:find_my_patterns/core/widgets/feeling_chips.dart';
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

  Entry entryAt(
    String id,
    DateTime createdAt,
    List<Feeling> feelings, {
    Map<String, int> intensities = const {},
  }) => Entry(
    id,
    createdAt,
    date,
    EntryMode.freeform,
    'something happened',
    feelings.isEmpty ? null : feelings.first,
    feelings,
    FeelingSource.confirmed,
    null,
    intensities,
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
    testWidgets('names the feeling that reached it: "Strongest: Grateful '
        '4/5"', (tester) async {
      await pumpCard(
        tester,
        entries: [
          entryAt(
            'a',
            DateTime.utc(2026, 8, 28, 9),
            [grateful],
            intensities: {'grateful': 4},
          ),
        ],
        summary: const DaySummary(date, [grateful], intensity: 4),
      );

      // Eyebrow upper-cases for display; its semantics still say
      // "Strongest" (see the whole-card spoken label below).
      expect(find.text('STRONGEST'), findsOneWidget);
      // The rating text lives only on the strongest row's own chip -- the
      // feelings row above draws the same feeling with no suffix at all --
      // so its ancestor chip is the one this assertion is actually about.
      final chip = find.ancestor(
        of: find.text('4/5'),
        matching: find.byType(FeelingChip),
      );
      expect(chip, findsOneWidget);
      expect(tester.widget<FeelingChip>(chip).label, 'Grateful');
    });

    testWidgets(
      'names the first feeling by day order and adds "+n" when several tie',
      (tester) async {
        await pumpCard(
          tester,
          entries: [
            // Grateful is on the earlier entry, so it is named first even
            // though anxious was chosen second within its own entry.
            entryAt(
              'a',
              DateTime.utc(2026, 8, 28, 9),
              [grateful],
              intensities: {'grateful': 4},
            ),
            entryAt(
              'b',
              DateTime.utc(2026, 8, 28, 21),
              [anxious],
              intensities: {'anxious': 4},
            ),
          ],
          summary: const DaySummary(date, [grateful, anxious], intensity: 4),
        );

        final chip = find.ancestor(
          of: find.text('4/5 +1'),
          matching: find.byType(FeelingChip),
        );
        expect(chip, findsOneWidget);
        expect(tester.widget<FeelingChip>(chip).label, 'Grateful');
      },
    );

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

        expect(find.text('STRONGEST'), findsNothing);
        expect(find.textContaining('/5'), findsNothing);
      },
    );

    testWidgets(
      'is absent when the entries on screen cannot account for the '
      "roll-up's number, rather than showing a rating with no name",
      (tester) async {
        // The roll-up says 4, but nothing loaded on screen was actually
        // rated 4 -- naming a feeling here would be a guess this client
        // has no business making.
        await pumpCard(
          tester,
          entries: [
            entryAt('a', DateTime.utc(2026, 8, 28, 9), [grateful]),
          ],
          summary: const DaySummary(date, [grateful], intensity: 4),
        );

        expect(find.text('STRONGEST'), findsNothing);
        expect(find.textContaining('/5'), findsNothing);
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
