import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/experiment.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:find_my_patterns/features/insights/pattern_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../experiments/fixtures.dart';
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
  Widget app(
    Pattern pattern, {
    void Function(String, CalendarDate)? onOpen,
    Experiment? activeExperiment,
    void Function(Pattern)? onTestPattern,
    bool isPremium = true,
    VoidCallback? onUpgrade,
  }) => MaterialApp(
    theme: buildLightTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: PatternCard(
          pattern: pattern,
          constants: buildConstants(),
          onOpenEntry: onOpen ?? (_, _) {},
          activeExperiment: activeExperiment,
          onTestPattern: onTestPattern,
          isPremium: isPremium,
          onUpgrade: onUpgrade,
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

  // Issue #24 task 3: tapping a confounder's annotation expands a small
  // split view in place, showing the 2x2 `Confounder` model from both
  // sides. See `_ConfounderSplit`'s doc comment in `pattern_card.dart` for
  // why "present/total" is `onlyThisCount`/`bothCount + onlyThisCount` for
  // the pattern's own topic and the mirror image for the confounder's
  // topic, rather than either side's share of the full 2x2.
  group('confounder split view', () {
    testWidgets(
      'the split is absent until the confounder note is tapped',
      (tester) async {
        await tester.pumpWidget(
          app(
            buildPattern(
              topic: 'coffee',
              confounders: [buildConfounder(topic: 'work')],
            ),
          ),
        );

        expect(
          find.text('Coffee and work often show up together.'),
          findsOneWidget,
        );
        expect(find.text('WITH COFFEE ONLY'), findsNothing);
        expect(find.text('WITH WORK ONLY'), findsNothing);
      },
    );

    testWidgets(
      'tapping the note reveals both mini-columns with the exact model '
      'counts',
      (tester) async {
        await tester.pumpWidget(
          app(
            buildPattern(
              topic: 'coffee',
              confounders: [
                buildConfounder(
                  topic: 'work',
                  bothCount: 9,
                  onlyThisCount: 1,
                  onlyOtherCount: 4,
                  neitherCount: 20,
                ),
              ],
            ),
          ),
        );

        await tester.tap(
          find.text('Coffee and work often show up together.'),
        );
        await tester.pumpAndSettle();

        expect(find.text('WITH COFFEE ONLY'), findsOneWidget);
        expect(find.text('WITH WORK ONLY'), findsOneWidget);
        // onlyThisCount of (bothCount + onlyThisCount): 1 of 10.
        expect(find.text('1 of 10 entries'), findsOneWidget);
        // onlyOtherCount of (bothCount + onlyOtherCount): 4 of 13.
        expect(find.text('4 of 13 entries'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping again collapses the split back down',
      (tester) async {
        await tester.pumpWidget(
          app(
            buildPattern(
              topic: 'coffee',
              confounders: [buildConfounder(topic: 'work')],
            ),
          ),
        );

        final noteFinder = find.text(
          'Coffee and work often show up together.',
        );
        await tester.tap(noteFinder);
        await tester.pumpAndSettle();
        expect(find.text('WITH WORK ONLY'), findsOneWidget);

        await tester.tap(noteFinder);
        await tester.pumpAndSettle();
        expect(find.text('WITH WORK ONLY'), findsNothing);
      },
    );

    testWidgets(
      'inseparable (onlyThisCount 0) explains itself instead of showing a '
      'bare zero',
      (tester) async {
        await tester.pumpWidget(
          app(
            buildPattern(
              topic: 'coffee',
              confounders: [
                buildConfounder(
                  topic: 'work',
                  bothCount: 9,
                  onlyThisCount: 0,
                  onlyOtherCount: 3,
                  inseparable: true,
                ),
              ],
            ),
          ),
        );

        await tester.tap(
          find.text('Coffee and work often show up together.'),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Not enough entries to separate yet'),
          findsOneWidget,
        );
        expect(find.text('0 of 9 entries'), findsNothing);
        // The other side is unaffected: onlyOtherCount of (bothCount +
        // onlyOtherCount), 3 of 12.
        expect(find.text('WITH WORK ONLY'), findsOneWidget);
        expect(find.text('3 of 12 entries'), findsOneWidget);
      },
    );

    testWidgets(
      'expanding one confounder does not expand another on the same card',
      (tester) async {
        await tester.pumpWidget(
          app(
            buildPattern(
              topic: 'coffee',
              confounders: [
                buildConfounder(topic: 'work', note: 'Confounder A.'),
                buildConfounder(topic: 'meetings', note: 'Confounder B.'),
              ],
            ),
          ),
        );

        await tester.tap(find.text('Confounder A.'));
        await tester.pumpAndSettle();

        expect(find.text('WITH WORK ONLY'), findsOneWidget);
        expect(find.text('WITH MEETINGS ONLY'), findsNothing);
      },
    );

    testWidgets(
      'a card without confounders shows no confounder annotation',
      (tester) async {
        await tester.pumpWidget(app(buildPattern()));

        expect(find.byIcon(Icons.link), findsNothing);
      },
    );

    testWidgets(
      'the expanded split renders inside a 320dp card at 2x text scale '
      'with no overflow',
      (tester) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: app(
              buildPattern(
                topic: 'a fairly long topic name',
                confounders: [
                  buildConfounder(
                    topic: 'another rather long topic',
                    note: 'Often shows up with another rather long topic.',
                    bothCount: 9,
                    onlyThisCount: 1,
                    onlyOtherCount: 4,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final noteFinder = find.text(
          'Often shows up with another rather long topic.',
        );
        await tester.ensureVisible(noteFinder);
        await tester.tap(noteFinder);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });

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
    // Singular, not "1 entries" -- the defect found on the live diary.
    expect(find.text('1 entry'), findsOneWidget);
    expect(find.text('1 entries'), findsNothing);

    await tester.tap(find.text('1 entry'));
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

    await tester.tap(find.text('1 entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));

    expect(openedId, 'entry-42');
    expect(openedDate, const CalendarDate(2026, 8, 20));
  });

  group('R-3b experiment action', () {
    testWidgets('shows nothing when onTestPattern is not given', (
      tester,
    ) async {
      await tester.pumpWidget(app(buildPattern()));

      expect(find.text('Test this pattern'), findsNothing);
      expect(find.text('EXPERIMENT RUNNING'), findsNothing);
    });

    testWidgets(
      '"Test this pattern" is offered when nothing is running, and taps '
      'call back with this pattern',
      (tester) async {
        Pattern? tapped;
        final pattern = buildPattern(topic: 'coffee');
        await tester.pumpWidget(
          app(pattern, onTestPattern: (p) => tapped = p),
        );

        expect(find.text('Test this pattern'), findsOneWidget);
        await tester.tap(find.text('Test this pattern'));
        expect(tapped, same(pattern));
      },
    );

    testWidgets(
      'shows "Experiment running" instead, once the active experiment is '
      "this card's own topic and feeling",
      (tester) async {
        final pattern = buildPattern(topic: 'coffee');
        await tester.pumpWidget(
          app(
            pattern,
            onTestPattern: (_) {},
            activeExperiment: buildExperiment(
              patternTopic: 'coffee',
              patternFeeling: pattern.feeling!.key,
            ),
          ),
        );

        expect(find.text('EXPERIMENT RUNNING'), findsOneWidget);
        expect(find.text('Test this pattern'), findsNothing);
      },
    );

    testWidgets(
      'still offers "Test this pattern" when a different pattern is the '
      'one running',
      (tester) async {
        final pattern = buildPattern(topic: 'coffee');
        await tester.pumpWidget(
          app(
            pattern,
            onTestPattern: (_) {},
            activeExperiment: buildExperiment(
              patternTopic: 'exercise',
              patternFeeling: pattern.feeling!.key,
            ),
          ),
        );

        expect(find.text('Test this pattern'), findsOneWidget);
        expect(find.text('EXPERIMENT RUNNING'), findsNothing);
      },
    );

    group('free tier (M-3, #48)', () {
      testWidgets(
        'offers "Test this pattern" for a premium account, as before',
        (tester) async {
          await tester.pumpWidget(
            app(buildPattern(), onTestPattern: (_) {}, isPremium: true),
          );

          expect(find.text('Test this pattern'), findsOneWidget);
          expect(find.text('Experiments — Premium'), findsNothing);
        },
      );

      testWidgets(
        'a free account sees an Upgrade prompt instead, and it never opens '
        'the setup sheet',
        (tester) async {
          Pattern? tappedForTest;
          var upgradeTapped = false;
          await tester.pumpWidget(
            app(
              buildPattern(),
              onTestPattern: (p) => tappedForTest = p,
              isPremium: false,
              onUpgrade: () => upgradeTapped = true,
            ),
          );

          expect(find.text('Test this pattern'), findsNothing);
          expect(find.byIcon(Icons.lock_outline), findsOneWidget);
          expect(find.text('Experiments — Premium'), findsOneWidget);
          // Rendered geometry, not just presence: the lock icon draws at
          // its given 18x18 size, and the row shrink-wraps to its label
          // rather than stretching across the card -- the same
          // `Align`-not-`Container(alignment:)` shape #111/#117 exist to
          // guard against elsewhere in this file's own strength-bar tests.
          expect(
            tester.getSize(find.byIcon(Icons.lock_outline)),
            const Size(18, 18),
          );
          final cardWidth = tester.getSize(find.byType(PatternCard)).width;
          final lockWidth = tester
              .getSize(find.widgetWithText(TextButton, 'Experiments — Premium'))
              .width;
          expect(lockWidth, lessThan(cardWidth));

          await tester.tap(find.text('Experiments — Premium'));

          expect(upgradeTapped, isTrue);
          expect(tappedForTest, isNull);
        },
      );

      testWidgets(
        'a running experiment still takes priority over the free-tier lock',
        (tester) async {
          final pattern = buildPattern(topic: 'coffee');
          await tester.pumpWidget(
            app(
              pattern,
              onTestPattern: (_) {},
              isPremium: false,
              activeExperiment: buildExperiment(
                patternTopic: 'coffee',
                patternFeeling: pattern.feeling!.key,
              ),
            ),
          );

          // A free account cannot have started this experiment in the
          // first place, but if the state ever disagreed, "it is already
          // running" is still the more useful fact to show than a lock on
          // an action that is not being offered anyway.
          expect(find.text('EXPERIMENT RUNNING'), findsOneWidget);
          expect(find.text('Experiments — Premium'), findsNothing);
        },
      );
    });
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
