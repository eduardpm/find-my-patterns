import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/monthly_summary.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/widgets/feeling_chips.dart';
import 'package:find_my_patterns/features/today/day_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../support/harness.dart';
import '../../support/rendered_text.dart';

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
                data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
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
    return (track: tester.getSize(barFinder), fill: tester.getSize(fillFinder));
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
      (tester) async {
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

    testWidgets('is absent when the entries on screen cannot account for the '
        "roll-up's number, rather than showing a rating with no name", (
      tester,
    ) async {
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
    });
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

  group('the count/time-span row (#131)', () {
    // The key on the row itself (see `day_summary_card.dart`'s
    // `daySummaryCountSpanRow`) -- finding it by type would also match the
    // "STRONGEST" row further down the card.
    const rowKey = ValueKey('daySummaryCountSpanRow');

    final format = DateFormat.jm();

    // A full day, from a 7:15 AM entry to a 10:40 PM one: the span reads
    // its longest realistic shape, "7:15 AM – 10:40 PM" -- as wide as this
    // card ever asks it to be. Ten filler entries at noon push the count to
    // two digits without touching the span's own two endpoints.
    //
    // Local (not `.utc`) `DateTime`s: the card runs every `createdAt`
    // through `.toLocal()` before formatting it, so a UTC fixture here would
    // format differently depending on the machine's own time zone offset --
    // exactly the kind of environment-dependent flake this file should not
    // introduce chasing a layout bug.
    final busyDayEntries = [
      entryAt('first', DateTime(2026, 8, 28, 7, 15), [grateful]),
      for (var i = 0; i < 10; i++)
        entryAt('mid$i', DateTime(2026, 8, 28, 12), [grateful]),
      entryAt('last', DateTime(2026, 8, 28, 22, 40), [grateful]),
    ];
    final busyDaySpan =
        '${format.format(DateTime(2026, 8, 28, 7, 15))} – '
        '${format.format(DateTime(2026, 8, 28, 22, 40))}';

    testWidgets(
      'the span sits flush against the row\'s own trailing edge when it '
      'fits on one line',
      (tester) async {
        await pumpCard(
          tester,
          entries: [
            entryAt('a', DateTime(2026, 8, 28, 7, 15), [grateful]),
          ],
        );

        final spanText = 'at ${format.format(DateTime(2026, 8, 28, 7, 15))}';
        final rowRight = tester.getTopRight(find.byKey(rowKey)).dx;
        final spanRight = tester.getTopRight(find.text(spanText)).dx;
        // The span's `Text` sits inside an `Expanded`, which gives it a
        // *tight* width constraint equal to whatever the row has left over
        // -- so its own rendered box reaches exactly to the row's trailing
        // edge regardless of `textAlign`, the same way `Spacer` used to
        // push a fixed-width `Text` there. `closeTo` rather than strict
        // equality only to absorb floating-point layout rounding.
        expect(spanRight, closeTo(rowRight, 0.5));
        // And it still shares the row with the count label rather than
        // sitting on a line of its own -- its top sits above the label's
        // bottom, i.e. the two vertically overlap.
        expect(
          tester.getTopLeft(find.text(spanText)).dy,
          lessThan(tester.getBottomLeft(find.text('entry')).dy),
        );
      },
    );

    testWidgets(
      'no overflow at 320dp width with a two-digit count and the longest '
      'realistic span',
      (tester) async {
        // 320dp at the default text scale -- the literal reproduction this
        // ticket names: "a narrower viewport, or a wide time span".
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pumpCard(tester, entries: busyDayEntries);

        expect(tester.takeException(), isNull);
        // The count is the fixed-ish side (#131's own reasoning for which
        // side yields) -- "12" must still read in full, never "1…".
        expect(find.text('12'), findsOneWidget);
        expect(find.text(busyDaySpan), findsOneWidget);
      },
    );

    testWidgets(
      'wraps the span to a second line under 360dp and 2x text scale, '
      'rather than overflowing or truncating a number',
      (tester) async {
        // A single-digit count here, not `busyDayEntries`' two-digit one:
        // at 2x text scale, a two-digit count plus "entries" already
        // claims more than a 360dp card's own content width by itself,
        // with nothing left for any span at all -- a real defect, but on
        // the *other* half of this row, and not the one #131 describes or
        // this fix touches. #137 (see the group below) is what closes
        // that half; a single-digit count here keeps this test about the
        // span, the thing #131's `Expanded` actually fixed, without the
        // two defects' fixes shadowing each other.
        final entries = [
          entryAt('a', DateTime(2026, 8, 28, 7, 15), [grateful]),
          entryAt('b', DateTime(2026, 8, 28, 12), [grateful]),
          entryAt('c', DateTime(2026, 8, 28, 22, 40), [grateful]),
        ];
        final span =
            '${format.format(DateTime(2026, 8, 28, 7, 15))} – '
            '${format.format(DateTime(2026, 8, 28, 22, 40))}';

        // Baseline: the same text, the same 2x scale, on a width roomy
        // enough that it still reads as one line -- so the height below is
        // compared against the *same* font size and only the width
        // actually changes.
        await pumpCard(tester, entries: entries, textScale: 2);
        expect(tester.takeException(), isNull);
        final singleLineHeight = tester.getSize(find.text(span)).height;

        tester.view.physicalSize = const Size(360, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpCard(tester, entries: entries, textScale: 2);

        // This is the assertion that would have failed before #131: the
        // unconstrained `Text` that used to sit after `Spacer()` never grew
        // taller than one line at any width -- it just overflowed the
        // `Row` horizontally instead (a `RenderFlex` exception here). No
        // exception, plus a measurably taller box, is what tells apart
        // "wrapped" from "overflowed and clipped".
        expect(tester.takeException(), isNull);
        final wrappedHeight = tester.getSize(find.text(span)).height;
        expect(wrappedHeight, greaterThan(singleLineHeight * 1.4));
        // Wrapping, not ellipsis -- the full string, digits included, is
        // still the one rendered.
        expect(find.text(span), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
      },
    );
  });

  group('the count/label pair at large text scale (#137)', () {
    // #137's own reproduction: at `textScale: 2.0`, a two-digit count plus
    // "entries" *alone* -- no span considered at all -- already outgrows a
    // 360dp card's own content width (~342px needed against ~312px
    // available). #131 only ever taught the *span* to yield; this is the
    // other half of the same row, the side #131's own PR assumed was
    // safely fixed-width and filed this ticket to revisit.
    //
    // Every entry below shares one timestamp, so `_timeSpan` always
    // resolves to the short "at 7:15 AM" form (`first == last`) -- this
    // group is about the count/label pair, not the span's own width, so
    // the span is kept as small and unrelated to the count as possible.
    final format = DateFormat.jm();
    final sameTimestamp = DateTime(2026, 8, 28, 7, 15);
    final expectedSpan = 'at ${format.format(sameTimestamp)}';

    List<Entry> entriesNumbering(int count) => [
      for (var i = 0; i < count; i++) entryAt('e$i', sameTimestamp, [grateful]),
    ];

    // One-digit and two-digit counts, the two shapes named in the issue.
    final oneDigitEntries = entriesNumbering(3);
    final twoDigitEntries = entriesNumbering(12);

    // Every combination the issue names: 320dp/360dp, 1x/2x text scale,
    // one-digit/two-digit counts. Whichever of the row's two shapes a
    // given cell picks, two invariants must hold regardless -- no
    // `RenderFlex` overflow, and the count survives in full, never
    // clipped to an ellipsis. Checking the full matrix (not just the one
    // 360dp/2x/two-digit cell the issue measured) is what stops a seventh
    // instance of this same family turning up in some other cell nobody
    // thought to run.
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final entries in [oneDigitEntries, twoDigitEntries]) {
          final count = entries.length;
          final label = count == 1 ? 'entry' : 'entries';
          testWidgets(
            '$count entries at ${width.toInt()}dp / ${scale}x text scale: '
            'no overflow, count shown in full',
            (tester) async {
              tester.view.physicalSize = Size(width, 1200);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);

              await pumpCard(tester, entries: entries, textScale: scale);

              expect(tester.takeException(), isNull);
              // `renderedText` reads a plain `Text('$count')` next to a
              // plain `Text('entries')` (the ordinary row) exactly the
              // same way it reads one `Text.rich` spanning both words
              // (the stacked row) -- this assertion does not need to
              // know which shape this cell picked.
              final onScreen = renderedText(tester);
              expect(onScreen, contains('$count'));
              expect(onScreen, contains(label));
              expect(onScreen, contains(expectedSpan));
            },
          );
        }
      }
    }

    testWidgets(
      'stacks the count/label pair onto its own line, span underneath, '
      'when the pair alone cannot share a 360dp row at 2x text scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pumpCard(tester, entries: twoDigitEntries, textScale: 2);

        expect(tester.takeException(), isNull);
        // The full, untruncated "12 entries" -- as one `Text.rich`, since
        // a standalone `Text('12')` no longer exists on this branch. This
        // is the assertion that pins the layout decision itself, not just
        // "nothing threw": a fix that shrank the count's font instead of
        // moving it to its own line would also clear the overflow, but
        // would fail this string-and-style check.
        final pairFinder = find.text('12 entries', findRichText: true);
        expect(pairFinder, findsOneWidget);
        // The span is not lost, just relocated -- it still renders in
        // full, strictly below the count/label pair rather than trailing
        // it on the same line the way #131's `Expanded` would place it.
        final spanFinder = find.text(expectedSpan);
        expect(spanFinder, findsOneWidget);
        expect(
          tester.getTopLeft(spanFinder).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(pairFinder).dy),
        );
      },
    );

    testWidgets(
      'stacks the count/label pair the same way at 320dp -- the pair\'s '
      'own width does not depend on how narrow the card is',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pumpCard(tester, entries: twoDigitEntries, textScale: 2);

        expect(tester.takeException(), isNull);
        expect(find.text('12 entries', findRichText: true), findsOneWidget);
        expect(find.text(expectedSpan), findsOneWidget);
      },
    );

    testWidgets(
      'keeps the ordinary one-line row -- count and label as separate '
      'widgets, span flush right -- when the pair still fits at 2x scale',
      (tester) async {
        // 360dp, not 320dp: measured directly, a single digit plus
        // "entries" fits this row's available width doubled at 360dp but
        // *not* at 320dp (the matrix loop above's "3 entries at 320dp /
        // 2.0x" cell is already on the stacked branch -- confirmed by
        // this same file's red run, where that exact cell failed against
        // the unfixed code too). The pair's fit is a real measurement,
        // not a "single digit always fits" assumption, so this test picks
        // the one width the matrix loop already proved keeps it inline.
        tester.view.physicalSize = const Size(360, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pumpCard(tester, entries: oneDigitEntries, textScale: 2);

        expect(tester.takeException(), isNull);
        // Two separate `Text`s, not one `Text.rich` -- the inverse of the
        // stacked-mode assertion above, pinning down that the ordinary
        // case really does keep #131's original widget shape rather than
        // the new branch always running.
        expect(find.text('3'), findsOneWidget);
        expect(find.text('entries'), findsOneWidget);
        expect(find.text('3 entries', findRichText: true), findsNothing);
      },
    );
  });

  group('card-wide audit at 2x text scale (#137)', () {
    // #131's own PR audited the feeling-chip row and the STRONGEST row at
    // 320dp and found them already safe, thanks to #111's shrink-wrapping
    // fix on `FeelingChip`. #137 exists precisely because nobody had
    // re-run that audit at 2x text scale before shipping -- this closes
    // that loop, rather than leaving "still safe" as another assumption
    // on file the way #131's own did for the count/label pair.
    testWidgets(
      'the feeling-chip row and the count/span row above it do not '
      'overflow at 2x text scale, at 320dp or 360dp, with a real '
      'two-endpoint span',
      (tester) async {
        // No rated intensity here on purpose -- isolates the `Wrap` of
        // `FeelingChip`s from the separate STRONGEST row below (see the
        // finding documented after this test), so a fix or regression in
        // one can't be misread as evidence about the other. This fixture
        // still exercises the count/span row from the group above, with a
        // full "9:00 AM – 9:00 PM" span rather than the short "at ..."
        // form -- confirmed (via this file's red run) to also overflow
        // against the unfixed code at 320dp, even with a single-digit
        // count: the fixed count/label pair alone already claims more of
        // this narrower row than #131's own matrix ever measured.
        for (final width in [320.0, 360.0]) {
          tester.view.physicalSize = Size(width, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await pumpCard(
            tester,
            entries: [
              entryAt('a', DateTime.utc(2026, 8, 28, 9), [grateful]),
              entryAt('b', DateTime.utc(2026, 8, 28, 21), [anxious]),
            ],
            summary: const DaySummary(date, [grateful, anxious]),
            textScale: 2,
          );

          expect(tester.takeException(), isNull, reason: 'at ${width}dp');
          expect(find.text('Grateful'), findsOneWidget);
          expect(find.text('Anxious'), findsOneWidget);
        }
      },
    );

    testWidgets(
      'the STRONGEST row does not overflow at 2x text scale on a 360dp '
      'card',
      (tester) async {
        tester.view.physicalSize = const Size(360, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pumpCard(
          tester,
          entries: [
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
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('STRONGEST'), findsOneWidget);
      },
    );
  });

  group('the STRONGEST row and its own overflow (#141)', () {
    // #137's own audit measured the STRONGEST row unsafe at 320dp/2x and
    // deliberately left it unasserted -- the `Eyebrow('Strongest')` + the
    // fixed 60px intensity bar + their two `JournalSpacing` gaps, all
    // non-flexible, measure ~304.6px by themselves against ~272px
    // available, a 33px overflow that happens *before* the trailing
    // `Flexible(FeelingChip(...))` gets any width at all.
    //
    // Measuring only the eyebrow and the bar (mirroring #137's own
    // pairWidth check) turned out to be an incomplete fix, caught by
    // running these tests against the unfixed row before writing the
    // real one (see the PR description for the actual red output): a
    // fixture with a two-name tie ("Grateful", intensity suffix
    // "4/5 +1") overflows by 54px at 320dp at the *default* text scale
    // alone, nowhere near 2x, and by 19px even for the shortest
    // single-name, untied case -- both well inside the bucket an
    // eyebrow-and-bar-only threshold would have called safe. The reason:
    // the chip's own intensity suffix is a plain `Text` next to its
    // `Flexible` label, not wrapped in one itself (never shrinks, never
    // wraps, the same anti-truncation rule that keeps every number on
    // this card whole), so it -- along with the dot, the chip's own
    // internal gaps, padding and border -- belongs in the row's
    // non-flexible sum exactly as much as the eyebrow and the bar do.
    // Only the chip's *label* can genuinely go to zero width. The row now
    // measures that full non-flexible sum, the same way #137 measured
    // the count/label pair, and moves the eyebrow to its own line
    // whenever that sum alone would not have fit.
    const barKey = ValueKey('daySummaryIntensityBar');
    const strongestRowKey = ValueKey('daySummaryStrongestRow');

    // Two entries tied at the same rating, so the chip's own intensity
    // suffix is the longer "4/5 +1" form rather than the shortest
    // possible "4/5" -- the same fixture #137's audit used for this row,
    // kept here so the matrix below and the structural assertions after
    // it exercise the label the row is actually widest with.
    final ratedEntries = [
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
    ];
    const ratedSummary = DaySummary(date, [grateful, anxious], intensity: 4);

    final unratedEntries = [
      entryAt('a', DateTime.utc(2026, 8, 28, 9), [grateful]),
    ];
    const unratedSummary = DaySummary(date, [grateful]);

    // The full matrix the issue asks for: 320dp/360dp x 1x/2x text scale x
    // with/without a rated intensity. A day with nothing rated never draws
    // this row at all (see 'the strongest rating' group above), so its
    // half of the matrix is "the row stays absent, nothing to overflow" --
    // included anyway so the loop, not a human, is the thing that decided
    // that cell is safe.
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final hasIntensity in [true, false]) {
          testWidgets(
            'no overflow at ${width.toInt()}dp / ${scale}x text scale, '
            '${hasIntensity ? 'with' : 'without'} a rated intensity',
            (tester) async {
              tester.view.physicalSize = Size(width, 1400);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);

              await pumpCard(
                tester,
                entries: hasIntensity ? ratedEntries : unratedEntries,
                summary: hasIntensity ? ratedSummary : unratedSummary,
                textScale: scale,
              );

              expect(
                tester.takeException(),
                isNull,
                reason:
                    'at ${width}dp / ${scale}x, '
                    '${hasIntensity ? 'with' : 'without'} a rating',
              );
              if (hasIntensity) {
                expect(find.text('STRONGEST'), findsOneWidget);
                // The full label and intensity suffix reach the screen,
                // not clipped to an ellipsis or dropped -- the same
                // "did the string actually paint" standard #137 checked
                // the count/label pair with, applied to this row's own
                // non-numeric pair.
                final onScreen = renderedText(tester);
                expect(onScreen, contains('Grateful'));
                expect(onScreen, contains('4/5 +1'));
              } else {
                // An unrated day draws no STRONGEST row at all -- nothing
                // here for this fix to have touched.
                expect(find.text('STRONGEST'), findsNothing);
              }
            },
          );
        }
      }
    }

    testWidgets(
      'moves the eyebrow to its own line above the bar and chip at 320dp '
      '/ 2x text scale -- the one cell where the eyebrow and bar do not '
      'fit on one line by themselves',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pumpCard(
          tester,
          entries: ratedEntries,
          summary: ratedSummary,
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        // The eyebrow's own line ends at or above where the bar's line
        // begins -- they do not share a row the way the ordinary case
        // does (checked below at 360dp).
        expect(
          tester.getBottomLeft(find.text('STRONGEST')).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byKey(barKey)).dy),
        );
        // The bar still reads as a proportional gauge -- #115's own
        // regression guard, unaffected by which line it now draws on.
        final sizes = barSizes(tester);
        expect(sizes.track, const Size(60, 4));
        expect(
          sizes.fill.width,
          closeTo(60 * (4 / EngineConstants.placeholder.maxIntensity), 1e-6),
        );
        // And the chip's label is not truncated -- FeelingChip's own
        // internal `Flexible` (#111) wraps whatever width it is offered
        // rather than clipping it.
        final onScreen = renderedText(tester);
        expect(onScreen, contains('Grateful'));
        expect(onScreen, contains('4/5 +1'));
      },
    );

    testWidgets(
      'keeps the eyebrow, bar and chip on one line at a width roomy '
      'enough for all three -- the ordinary case #137 established still '
      'exists, just not at any width in the issue\'s own matrix',
      (tester) async {
        // No `tester.view.physicalSize` override -- the default test
        // surface is wide enough (~800dp) that even this row's widest
        // fixture (a two-name tie, "4/5 +1") clears every non-flexible
        // measurement below with room to spare. #131's own audit called
        // the STRONGEST row "safe at 320dp" against a plain, untied
        // rating; measuring this row's *actual* floor (see the matrix
        // loop's own comment below) instead shows every cell in the
        // issue's 320/360dp matrix is a compound case once the chip's
        // own un-`Flexible` intensity suffix is counted honestly -- the
        // ordinary case this ticket preserves lives at wider widths than
        // either #131 or #137 had reason to check.
        await pumpCard(tester, entries: ratedEntries, summary: ratedSummary);

        expect(tester.takeException(), isNull);
        // The eyebrow and the bar sit on the same line -- their vertical
        // centres line up, unlike the 320dp/2x compound case above.
        expect(
          tester.getCenter(find.text('STRONGEST')).dy,
          closeTo(tester.getCenter(find.byKey(barKey)).dy, 1),
        );
        // Still one `LayoutBuilder`-built row rather than a stacked
        // column -- confirms the ordinary branch, not just "something
        // that happens to align", is what rendered.
        expect(find.byKey(strongestRowKey), findsOneWidget);
      },
    );
  });
}
