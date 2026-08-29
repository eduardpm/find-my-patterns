import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/features/insights/pattern_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  Widget app(Pattern pattern, {void Function(String, CalendarDate)? onOpen}) =>
      MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PatternCard(
              pattern: pattern,
              constants: buildConstants(),
              onOpenEntry: onOpen ?? (_, _) {},
            ),
          ),
        ),
      );

  testWidgets('shows the topic capitalised, the narrative and the suggestion', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        buildPattern(
          topic: 'coffee',
          narrativeText: 'A narrative.',
          suggestionText: 'A suggestion.',
        ),
      ),
    );

    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('A narrative.'), findsOneWidget);
    expect(find.text('A suggestion.'), findsOneWidget);
  });

  testWidgets('reads "Consider changing" for a change direction', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(buildPattern(direction: PatternDirection.change)),
    );
    expect(find.text('CONSIDER CHANGING'), findsOneWidget);
  });

  testWidgets('reads "Keep doing" for a keep direction', (tester) async {
    await tester.pumpWidget(
      app(buildPattern(direction: PatternDirection.keep)),
    );
    expect(find.text('KEEP DOING'), findsOneWidget);
  });

  // P0-2: a neutral-valence feeling has no positive signal to reinforce and
  // no negative one to discourage, so the card shows neither badge rather
  // than defaulting to one.
  testWidgets('shows no direction badge for a neutral-valence pattern', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(buildPattern(direction: PatternDirection.none)),
    );
    expect(find.text('KEEP DOING'), findsNothing);
    expect(find.text('CONSIDER CHANGING'), findsNothing);
  });

  // P0-6: a badge-less card carries no tip strip either -- advice built on a
  // ratio the card itself cannot state (or, as here, on a feeling with no
  // signal either way) is exactly the claim-with-no-number the rest of the
  // app refuses to make. The counts and the narrative stay untouched; only
  // the advisory strip goes quiet.
  testWidgets(
    'shows no suggestion strip either when there is no badge to back it',
    (tester) async {
      await tester.pumpWidget(
        app(
          buildPattern(
            direction: PatternDirection.none,
            suggestionText:
                'Pay attention to how tea affects your neutral feeling.',
          ),
        ),
      );
      expect(
        find.text('Pay attention to how tea affects your neutral feeling.'),
        findsNothing,
      );
    },
  );

  // The exact bug this ticket fixes, reproduced at the widget level: a card
  // whose lift is undefined -- so `direction` arrives from the backend as
  // `none`, per `badgeDirectionFor` -- shows its "LIFT —" figure, its counts
  // and its explanation, but neither badge nor tip strip.
  testWidgets(
    'a card with an undefined lift keeps its counts and explanation but '
    'shows neither badge nor suggestion strip',
    (tester) async {
      await tester.pumpWidget(
        app(
          buildPattern(
            topic: 'work',
            direction: PatternDirection.none,
            lift: null,
            presentCount: 4,
            presentTotal: 4,
            absentCount: 0,
            absentTotal: 7,
            presentRate: 1.0,
            absentRate: 0.0,
            comparisonReason: 'no_absent_occurrences',
            comparisonNote: 'This feeling does not appear in any entry without work, so there is no ratio to state.',
            suggestionText:
                'Pay attention to how work affects your anxious feeling.',
          ),
        ),
      );

      // The badge and the tip are gone.
      expect(find.text('KEEP DOING'), findsNothing);
      expect(find.text('CONSIDER CHANGING'), findsNothing);
      expect(
        find.text('Pay attention to how work affects your anxious feeling.'),
        findsNothing,
      );

      // Everything the card can actually state stays on screen.
      expect(find.text('4/4'), findsOneWidget);
      expect(find.text('0/7'), findsOneWidget);
      expect(find.text('—'), findsOneWidget); // the lift figure itself
      expect(
        find.text(
          'This feeling does not appear in any entry without work, so there is no ratio to state.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shows "Without it" for an inverse pattern and swaps the strength labels',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        app(buildPattern(kind: PatternKind.inverse, topic: 'coffee')),
      );

      expect(find.text('WITHOUT IT'), findsOneWidget);
      // The stat labels are rendered through `Eyebrow`, which upper-cases for
      // display -- see `Eyebrow`'s own doc comment for why that is safe for
      // the accessibility tree even though it changes what `find.text` sees.
      expect(find.text('WITHOUT COFFEE'), findsOneWidget);
      expect(find.text('WITH COFFEE'), findsOneWidget);
    },
  );

  testWidgets('shows "Historical" and "Strong" badges when applicable', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(buildPattern(status: PatternStatus.historical, isStrong: true)),
    );

    expect(find.text('HISTORICAL'), findsOneWidget);
    expect(find.text('STRONG'), findsOneWidget);
  });

  testWidgets(
    'renders a null rate and a null lift as an em dash, never a number',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        app(buildPattern(presentRate: null, absentRate: 0.5, lift: null)),
      );

      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('50%'), findsOneWidget);
    },
  );

  testWidgets('rounds a rate to a whole percent and a lift to one decimal', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        buildPattern(
          presentRate: 0.8,
          absentRate: 0.24,
          baseRate: 0.333,
          lift: 2.45,
        ),
      ),
    );

    expect(find.text('80%'), findsOneWidget);
    expect(find.text('24%'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.text('2.5×'), findsOneWidget);
  });

  testWidgets(
    'shows a comparison note, a historical note and each confounder note',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          buildPattern(
            comparisonNote: 'Not enough entries to compare.',
            historicalNote: 'Last held 45 days ago.',
            confounders: [buildConfounder(note: 'Often shows up with work.')],
          ),
        ),
      );

      expect(find.text('Not enough entries to compare.'), findsOneWidget);
      expect(find.text('Last held 45 days ago.'), findsOneWidget);
      expect(find.text('Often shows up with work.'), findsOneWidget);
    },
  );

  testWidgets(
    'the footer reads singular for one occurrence and hides the lifetime '
    'count when it matches the windowed count',
    (tester) async {
      await tester.pumpWidget(
        app(buildPattern(occurrenceCount: 1, lifetimeCount: 1)),
      );

      // Rendered through `Eyebrow`, which upper-cases for display.
      expect(find.text('1 TIME IN 30 DAYS'), findsOneWidget);
    },
  );

  testWidgets('the footer appends the lifetime count when it differs from the '
      'windowed count', (tester) async {
    await tester.pumpWidget(
      app(buildPattern(occurrenceCount: 4, lifetimeCount: 9)),
    );

    expect(find.text('4 TIMES IN 30 DAYS · 9 IN TOTAL'), findsOneWidget);
  });

  testWidgets('the evidence trail is collapsed until the toggle is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        buildPattern(
          evidence: [buildEvidence(rawText: 'A supporting entry.')],
        ),
      ),
    );

    expect(find.text('A supporting entry.'), findsNothing);
    expect(find.text('1 entries'), findsOneWidget);

    await tester.tap(find.text('1 entries'));
    await tester.pumpAndSettle();

    expect(find.text('A supporting entry.'), findsOneWidget);
    expect(find.text('Hide entries'), findsOneWidget);

    await tester.tap(find.text('Hide entries'));
    await tester.pumpAndSettle();

    expect(find.text('A supporting entry.'), findsNothing);
  });

  testWidgets(
    'an empty evidence trail explains the pattern is built on older entries',
    (
      tester,
    ) async {
      await tester.pumpWidget(app(buildPattern()));

      await tester.tap(find.text('0 entries'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Nothing in the last 30 days. This pattern is built on older entries.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('opening an evidence row passes both the entry id and its date', (
    tester,
  ) async {
    String? openedId;
    CalendarDate? openedDate;
    await tester.pumpWidget(
      app(
        buildPattern(
          evidence: [
            buildEvidence(
              entryId: 'entry-42',
              entryDate: const CalendarDate(2026, 8, 20),
            ),
          ],
        ),
        onOpen: (id, date) {
          openedId = id;
          openedDate = date;
        },
      ),
    );

    await tester.tap(find.text('1 entries'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));

    expect(openedId, 'entry-42');
    expect(openedDate, const CalendarDate(2026, 8, 20));
  });

  // P0-2: `patternBadgeFor` is the single function that decides which badge
  // a card shows, kept separately testable (no `BuildContext` needed) so
  // ticket P0-6 can extend it with another reason to return no badge.
  group('patternBadgeFor', () {
    test('keep and change pass straight through', () {
      expect(
        patternBadgeFor(buildPattern(direction: PatternDirection.keep)),
        PatternDirection.keep,
      );
      expect(
        patternBadgeFor(buildPattern(direction: PatternDirection.change)),
        PatternDirection.change,
      );
    });

    test('a neutral-valence pattern (none) becomes no badge at all', () {
      expect(
        patternBadgeFor(buildPattern(direction: PatternDirection.none)),
        isNull,
      );
    });
  });
}
