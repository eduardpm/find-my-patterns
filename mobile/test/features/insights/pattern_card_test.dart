import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:find_my_patterns/features/insights/pattern_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// The WCAG contrast ratio between two colours, via [Color.computeLuminance]
/// -- the same helper `feeling_chip_test.dart` and
/// `calendar_day_cell_test.dart` each keep their own copy of, for the same
/// 3:1/4.5:1 checks `journal_palette.dart`'s doc comment promises.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final brighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (brighter + 0.05) / (darker + 0.05);
}

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

  testWidgets('shows the topic capitalised and the narrative', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(buildPattern(topic: 'coffee', narrativeText: 'A narrative.')),
    );

    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('A narrative.'), findsOneWidget);
  });

  // UX-2: the template tip strip -- the same "Pay attention to how X
  // affects your Y feeling" sentence on every card, regardless of what the
  // card actually found -- no longer exists anywhere, badge or no badge.
  // R-1 fills that slot later with recommendations that cite the user's own
  // data; until then, no tip is better than a fake one.
  testWidgets(
    'never shows the suggestion text, even for a badged card',
    (tester) async {
      await tester.pumpWidget(
        app(
          buildPattern(
            direction: PatternDirection.change,
            suggestionText: 'A suggestion.',
          ),
        ),
      );

      expect(find.text('A suggestion.'), findsNothing);
      expect(find.text('CONSIDER CHANGING'), findsOneWidget);
    },
  );

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
  // `none`, per `badgeDirectionFor` -- still draws both bars (CH-4, point 3:
  // 0% is drawable), keeps its counts and its explanation, but shows neither
  // a badge, a suggestion strip, nor a lift figure.
  testWidgets(
    'a card with an undefined lift keeps its counts and explanation but '
    'shows neither badge, suggestion strip, nor a lift figure',
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

      // Both bars still render -- 100% and 0% are both drawable rates -- and
      // the exact counts behind them are never hidden.
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('4/4'), findsOneWidget);
      expect(find.text('0/7'), findsOneWidget);
      // No lift figure: undefined lift is gated on the same signal as the
      // badge (P0-6), so there is nothing between the bars to print.
      expect(find.textContaining('more likely'), findsNothing);
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
    'renders a null rate as an em dash, never a number, but still draws '
    'that bar at 0%',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        app(buildPattern(presentRate: null, absentRate: 0.5)),
      );

      // The percent label never fabricates a number for a rate that could
      // not be computed...
      expect(find.text('—'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      // ...but the bar underneath it still renders, filled to 0% rather
      // than left out (point 3: 0% is drawable).
      final fractions = tester
          .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .map((box) => box.widthFactor)
          .toList();
      expect(fractions, containsAll(<double?>[0.0, 0.5]));
    },
  );

  testWidgets(
    'rounds a rate to a whole percent, the usual rate to a whole percent, '
    'and the lift to one decimal with "more likely"',
    (tester) async {
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
      expect(find.text('Usual rate: 33%'), findsOneWidget);
      expect(find.text('2.5× more likely'), findsOneWidget);
    },
  );

  testWidgets(
    'the bars are proportional to their rates, on a shared 0-100% scale',
    (tester) async {
      await tester.pumpWidget(
        app(buildPattern(presentRate: 0.5, absentRate: 0.1)),
      );

      final fractions = tester
          .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .map((box) => box.widthFactor)
          .toList();
      expect(fractions, [0.5, 0.1]);
    },
  );

  testWidgets(
    'each bar exposes one semantics sentence with the label, the feeling, '
    'the count and the percent',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          buildPattern(
            topic: 'walking',
            feeling: buildFeeling(label: 'Calm'),
            presentCount: 3,
            presentTotal: 6,
            presentRate: 0.5,
            absentCount: 1,
            absentTotal: 10,
            absentRate: 0.1,
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
          'With walking: calm in 3 of 6 entries, 50 percent',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Without walking: calm in 1 of 10 entries, 10 percent',
        ),
        findsOneWidget,
      );
      handle.dispose();
    },
  );

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

  // CH-4: the strength bars replace the old text-only stat grid, so they get
  // the same "every palette, both themes, no golden image" proof the rest
  // of the widgets in this app rely on -- see `feeling_chip_test.dart` and
  // `calendar_day_cell_test.dart` for the same call.
  group('strength bars — every theme', () {
    for (final palette in JournalPalette.values) {
      for (final dark in [false, true]) {
        final theming = '${palette.id} ${dark ? 'dark' : 'light'}';

        testWidgets(
          'renders both bars and the lift figure with no overflow at 320dp '
          'and 2x text scale in $theming',
          (tester) async {
            await tester.pumpWidget(
              MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 800),
                  textScaler: TextScaler.linear(2),
                ),
                child: MaterialApp(
                  theme: dark
                      ? buildDarkTheme(palette: palette)
                      : buildLightTheme(palette: palette),
                  home: Scaffold(
                    body: SingleChildScrollView(
                      child: PatternCard(
                        pattern: buildPattern(
                          topic: 'a fairly long topic name',
                        ),
                        constants: buildConstants(),
                        onOpenEntry: (_, _) {},
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.text('80%'), findsOneWidget);
            expect(find.text('24%'), findsOneWidget);
            expect(find.text('2.4× more likely'), findsOneWidget);
          },
        );
      }
    }
  });

  group('strength bars — colour contrast', () {
    // Point 4: the bar fill (the feeling's valence colour) and the track
    // (a surface token) must both clear 3:1 against the panel's own
    // background in every palette, both themes -- the same walk
    // `feeling_chip_test.dart`'s valence-colour group does for the 4.5:1
    // text rule.
    test(
      'every feeling hue (the fill) clears 3:1 against the panel background',
      () {
        for (final palette in JournalPalette.values) {
          for (final dark in [false, true]) {
            final colors = palette.colors(dark: dark);
            final panelBackground = colors.surfaceVariant;
            final hues = [
              colors.feelings.uplifted,
              colors.feelings.steady,
              colors.feelings.tense,
              colors.feelings.low,
            ];
            for (final hue in hues) {
              final ratio = _contrastRatio(hue, panelBackground);
              expect(
                ratio,
                greaterThanOrEqualTo(3.0),
                reason:
                    '${palette.id} ${dark ? 'dark' : 'light'}: $hue on '
                    '$panelBackground only clears ${ratio.toStringAsFixed(2)}:1',
              );
            }
          }
        }
      },
    );

    test(
      'the track colour (onSurfaceVariant) clears 3:1 against the panel '
      'background',
      () {
        for (final palette in JournalPalette.values) {
          for (final dark in [false, true]) {
            final colors = palette.colors(dark: dark);
            final ratio = _contrastRatio(
              colors.onSurfaceVariant,
              colors.surfaceVariant,
            );
            expect(
              ratio,
              greaterThanOrEqualTo(3.0),
              reason:
                  '${palette.id} ${dark ? 'dark' : 'light'}: track colour '
                  'only clears ${ratio.toStringAsFixed(2)}:1',
            );
          }
        }
      },
    );
  });

  group('patternBarFraction', () {
    test('a null rate draws as 0%, never a gap', () {
      expect(patternBarFraction(null), 0.0);
    });

    test('a defined rate passes through unchanged', () {
      expect(patternBarFraction(0.5), 0.5);
      expect(patternBarFraction(0.0), 0.0);
      expect(patternBarFraction(1.0), 1.0);
    });

    test('clamps to 0..1 defensively', () {
      expect(patternBarFraction(-0.2), 0.0);
      expect(patternBarFraction(1.4), 1.0);
    });
  });
}
