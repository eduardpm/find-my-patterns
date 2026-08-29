import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/monthly_summary.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/widgets/feeling_chips.dart';
import 'package:find_my_patterns/features/today/day_summary_card.dart';
import 'package:flutter/material.dart';
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
    double textScale = 1,
  }) async {
    final card = DaySummaryCard(
      entries: entries,
      summary: summary,
      isToday: isToday,
    );
    await tester.pumpWidget(
      // A bare `Harness().wrap` has no way to override the ambient text
      // scale, so a scale other than the default goes through `scope`
      // directly with the `MediaQuery` the wrap would otherwise supply.
      textScale == 1
          ? Harness().wrap(card)
          : Harness().scope(
              MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(textScale),
                ),
                child: MaterialApp(home: Scaffold(body: card)),
              ),
            ),
    );
    await tester.pumpAndSettle();
  }

  /// The key on the card's own intensity bar (see `_IntensityBar`,
  /// rendered at day_summary_card.dart:150) -- the widget had no `Key` at
  /// all before #115, which is exactly why the bar could paint zero
  /// pixels for as long as it did without a test noticing.
  const barKey = ValueKey('daySummaryIntensityBar');

  /// The rendered [Size] of the intensity bar's track and its coloured
  /// fill, read with `tester.getSize` -- what was actually laid out and
  /// painted, not a widget's requested `widthFactor`. #108/#115: a
  /// `Stack`'s loose constraints let the fill's `FractionallySizedBox`
  /// request the right `widthFactor` and still collapse to a literal
  /// `Size(_, 0.0)`, so a track or fill with zero height here is exactly
  /// the regression this ticket closes. Follows
  /// `calendar_day_cell_test.dart`'s `barSizes` helper for style.
  ({Size track, Size fill}) barSizes(WidgetTester tester) {
    final barFinder = find.byKey(barKey);
    final fillFinder = find.descendant(
      of: barFinder,
      matching: find.byType(FractionallySizedBox),
    );
    return (
      track: tester.getSize(barFinder),
      fill: tester.getSize(fillFinder),
    );
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

  group('the intensity bar', () {
    // Every case below drives a real rating through the card rather than
    // building `_IntensityBar` directly -- it is a private class, and the
    // only way it ever gets a value in production is `strongest != null`,
    // which needs an entry whose own recorded rating equals the roll-up's
    // `intensity`. Skipping that path is exactly how #115 shipped: the
    // widget's own `widthFactor` was correct the whole time it painted
    // zero pixels, so a test that does not measure rendered geometry
    // proves nothing.
    final maxIntensity = EngineConstants.placeholder.maxIntensity;

    testWidgets(
      'paints a non-zero track and a proportional fill at a mid rating',
      (tester) async {
        await pumpCard(
          tester,
          entries: [
            entryAt(
              'a',
              DateTime.utc(2026, 8, 28, 9),
              [grateful],
              intensities: {'grateful': 3},
            ),
          ],
          summary: const DaySummary(date, [grateful], intensity: 3),
        );

        final sizes = barSizes(tester);
        expect(sizes.track, const Size(60, 4));
        expect(sizes.fill.height, 4);
        expect(sizes.fill.width, closeTo(60 * (3 / maxIntensity), 1e-6));
      },
    );

    testWidgets('draws an empty fill at intensity 0, not a hidden bar', (
      tester,
    ) async {
      await pumpCard(
        tester,
        entries: [
          entryAt(
            'a',
            DateTime.utc(2026, 8, 28, 9),
            [grateful],
            intensities: {'grateful': 0},
          ),
        ],
        summary: const DaySummary(date, [grateful], intensity: 0),
      );

      final sizes = barSizes(tester);
      expect(sizes.track, const Size(60, 4));
      expect(sizes.fill.width, 0);
    });

    testWidgets('fills the whole track at the backend-supplied maximum', (
      tester,
    ) async {
      await pumpCard(
        tester,
        entries: [
          entryAt(
            'a',
            DateTime.utc(2026, 8, 28, 9),
            [grateful],
            intensities: {'grateful': maxIntensity},
          ),
        ],
        summary: DaySummary(date, const [grateful], intensity: maxIntensity),
      );

      final sizes = barSizes(tester);
      expect(sizes.track, const Size(60, 4));
      expect(sizes.fill.width, closeTo(60, 1e-6));
    });

    testWidgets(
      'still paints at double text scale, with the whole row laid out',
      (tester) async {
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
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        final sizes = barSizes(tester);
        // The bar's own SizedBox is fixed in logical pixels, so a larger
        // text scale must not shrink or clip it -- only the label text
        // beside it grows.
        expect(sizes.track, const Size(60, 4));
        expect(sizes.fill.width, closeTo(60 * (4 / maxIntensity), 1e-6));
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
