import 'package:flutter/material.dart';
// `intl` exports its own `TextDirection` (LTR/RTL/UNKNOWN, unrelated to
// Flutter's), which otherwise shadows `dart:ui`'s -- the one `TextPainter`
// below actually needs -- since both come in unprefixed. Nothing in this
// file formats bidi text, so hiding it is free.
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/diary/entry.dart';
import '../../core/diary/feeling.dart';
import '../../core/diary/monthly_summary.dart';
import '../../core/diary/pattern.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/theme/journal_typography.dart';
import '../../core/widgets/feeling_accent.dart';
import '../../core/widgets/feeling_chips.dart';
import '../../core/widgets/journal.dart';

/// The strongest rating this card's own bar is drawn against.
///
/// Same reasoning as `calendar_screen.dart`'s `_barMaxIntensity` (#108):
/// this card does not fetch Insights' own served constants just to size a
/// 4-pixel-tall bar, so it reads the placeholder's `maxIntensity` instead
/// of a bare `5` — at least naming where the number comes from, and
/// tracking the day the backend's dial stops being 1-5.
final int _barMaxIntensity = EngineConstants.placeholder.maxIntensity;

/// [_IntensityBar]'s own fixed width (#115's proportional-gauge contract --
/// see that class's doc comment). Named here too, rather than a second
/// literal `60`, so the STRONGEST row's own overflow measurement (#141)
/// cannot drift from the bar it is actually measuring around.
const double _intensityBarWidth = 60;

/// [FeelingDot]'s own default diameter (`journal.dart`) -- the value the
/// STRONGEST row's [FeelingChip] draws its dot at, since no call site here
/// overrides it. Named for the same reason as [_intensityBarWidth]: the
/// row's own overflow measurement (#141) reads this number rather than
/// reaching into [FeelingChip] to ask it.
const double _feelingDotSize = 10;

/// What the day amounted to, above the entries it is made of.
///
/// The count and time span are counted from [entries] already on the page;
/// the feelings and the strongest rating are read from the backend's own
/// day roll-up ([summary]) rather than counted here — never a statistic
/// this client invented. [summary]'s feelings are the fallback for a
/// summary that has not arrived yet, and are the same facts read off the
/// same entries either way.
///
/// The whole card carries one spoken description rather than letting a
/// screen reader walk its parts one at a time.
class DaySummaryCard extends StatelessWidget {
  /// Builds the summary card for [entries] on a day described by [summary]
  /// (or not, if that call has not landed).
  const DaySummaryCard({
    super.key,
    required this.entries,
    required this.summary,
    required this.isToday,
  });

  /// The entries on screen for this day.
  final List<Entry> entries;

  /// The backend's roll-up for this day, or `null` if it has not arrived.
  final DaySummary? summary;

  /// Whether the day being summarised is today.
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    final theme = Theme.of(context);
    final count = entries.length;
    final times = [for (final entry in entries) entry.createdAt.toLocal()]
      ..sort();
    final first = times.isEmpty ? null : times.first;
    final last = times.isEmpty ? null : times.last;
    final feelings = (summary?.feelings.isNotEmpty ?? false)
        ? summary!.feelings
        : _distinctFeelings(entries);
    final intensity = summary?.intensity;
    // The roll-up says *how much* the day registered but never *which*
    // feeling reached it -- naming it falls to the entries' own per-feeling
    // ratings, the same facts the fallback above already trusts. A day
    // whose entries cannot account for the roll-up's own number (a summary
    // that outran the entries load, say) hides the row rather than naming
    // it wrong.
    final strongest = intensity == null
        ? null
        : _strongestFeeling(entries, intensity);

    final spanText = _timeSpan(count, first, last);
    final countText = count == 1 ? '1 entry' : '$count entries';

    final spoken = StringBuffer(isToday ? 'The day so far. ' : 'The day. ')
      ..write(countText);
    if (spanText != null) spoken.write(', $spanText');
    if (feelings.isNotEmpty) {
      spoken.write('. ${feelings.map((f) => f.label).join(', ')}');
    }
    if (strongest != null) {
      spoken.write('. Strongest: ${strongest.feeling.label} $intensity/5');
      if (strongest.tiedCount > 0) {
        spoken.write(', plus ${strongest.tiedCount} more at the same rating');
      }
    }

    return Semantics(
      container: true,
      label: spoken.toString(),
      child: ExcludeSemantics(
        child: JournalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(isToday ? 'The day so far' : 'The day'),
              const SizedBox(height: JournalSpacing.x2),
              LayoutBuilder(
                // Keyed so `day_summary_card_test.dart` can measure this
                // row's own rendered geometry directly (#131) -- the same
                // reason `_IntensityBar` picked up a key for #115: a test
                // that only finds widgets by type risks matching the wrong
                // `Row` once the card has more than one. The key moved
                // here from the inner `Row` when #137 gave this area a
                // second possible shape (below): a `LayoutBuilder` reports
                // whatever size its built child comes back with, so every
                // existing `getSize`/`getTopRight` call against this key
                // keeps reading the same rendered box either way.
                key: const ValueKey('daySummaryCountSpanRow'),
                builder: (context, constraints) {
                  final countStyle = JournalType.tabularFigures(
                    theme.textTheme.displaySmall!,
                  ).copyWith(color: theme.colorScheme.primary);
                  final labelText = count == 1 ? 'entry' : 'entries';
                  final labelStyle = theme.textTheme.bodyMedium?.copyWith(
                    color: journal.onSurfaceVariant,
                  );
                  final spanStyle = JournalType.tabularFigures(
                    theme.textTheme.bodySmall!,
                  ).copyWith(color: journal.onSurfaceVariant);

                  // #137: the compound worst case #131 explicitly left
                  // out -- a two-digit count plus "entries" *alone*, no
                  // span involved yet, already outgrowing a 360dp card's
                  // own content width at 2x text scale (~342px needed
                  // against ~312px available). Measuring the pair at the
                  // exact `TextStyle` and `TextScaler` this build is
                  // actually using answers the only question that
                  // matters -- does this pair fit *this* row, right now --
                  // instead of guessing from a hardcoded "two digits at
                  // 2x" threshold that the next locale or font tweak could
                  // quietly invalidate.
                  final scaler = MediaQuery.textScalerOf(context);
                  final pairWidth =
                      _measure('$count', countStyle, scaler) +
                      JournalSpacing.x2 +
                      _measure(labelText, labelStyle, scaler);

                  if (pairWidth <= constraints.maxWidth) {
                    // Ordinary case, #131 untouched: the count and its
                    // label are the fixed-ish side (a digit plus
                    // "entry"/"entries" never grows past two short
                    // words), so they stay un-flexible and the span --
                    // the side whose width actually varies with the
                    // day's data -- is what yields. `Expanded` (not
                    // `Flexible`) is required to still hug the row's
                    // trailing edge when there is room: a bare
                    // `Flexible` does not claim the leftover main-axis
                    // space the way a `Spacer` used to, so the span
                    // would sit immediately after the count instead of
                    // at the right. It wraps to a second line rather
                    // than truncating -- the product rule against
                    // clipping a number applies to the span's clock
                    // times as much as it does to the entry count.
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$count', style: countStyle),
                        const SizedBox(width: JournalSpacing.x2),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(labelText, style: labelStyle),
                        ),
                        if (spanText != null)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                spanText,
                                textAlign: TextAlign.right,
                                style: spanStyle,
                              ),
                            ),
                          ),
                      ],
                    );
                  }

                  // Compound worst case: the count and its label do not
                  // fit *by themselves*, so no split of the row's
                  // leftover space could ever have saved it -- #131's
                  // `Expanded` assumes there is a positive amount of
                  // leftover main-axis space to hand the span, and here
                  // there is none, even with no span at all. Truncating
                  // "12" is off the table (the product rule that every
                  // claim shows its numbers in full), and shrinking the
                  // count's own type fights the accessibility scale the
                  // user just asked for by choosing it -- so the fix
                  // moves to the other axis instead. The count and its
                  // label become one `Text.rich`, which -- like any
                  // wrapped `Text` -- breaks at the word boundary between
                  // them if even the pair alone cannot share a line at
                  // some more extreme scale, rather than clipping either
                  // one. The span, if there is one, drops to a line of
                  // its own underneath: there is no longer a shared line
                  // for it to trail on, so it is left-aligned rather than
                  // right-aligned the way the ordinary case's `Expanded`
                  // leaves it.
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '$count', style: countStyle),
                            const TextSpan(text: ' '),
                            TextSpan(text: labelText, style: labelStyle),
                          ],
                        ),
                      ),
                      if (spanText != null) ...[
                        const SizedBox(height: JournalSpacing.x1),
                        Text(spanText, style: spanStyle),
                      ],
                    ],
                  );
                },
              ),
              if (feelings.isNotEmpty || strongest != null) ...[
                const SizedBox(height: JournalSpacing.x4),
                Divider(color: journal.hairline, height: 1),
                const SizedBox(height: JournalSpacing.x4),
              ],
              if (feelings.isNotEmpty)
                Wrap(
                  spacing: JournalSpacing.x2,
                  runSpacing: JournalSpacing.x2,
                  children: [
                    for (final feeling in feelings)
                      FeelingChip(
                        label: feeling.label,
                        color: feeling.accent(journal),
                      ),
                  ],
                ),
              if (strongest != null) ...[
                const SizedBox(height: JournalSpacing.x3),
                LayoutBuilder(
                  // Keyed for the same reason `daySummaryCountSpanRow` is
                  // (#131, #137, above): a test that only finds widgets by
                  // type risks matching the wrong row once the card has
                  // more than one.
                  key: const ValueKey('daySummaryStrongestRow'),
                  builder: (context, constraints) {
                    final intensityLabel = strongest.tiedCount > 0
                        ? '$intensity/5 +${strongest.tiedCount}'
                        : '$intensity/5';
                    final bar = _IntensityBar(
                      key: const ValueKey('daySummaryIntensityBar'),
                      intensity: intensity!,
                    );
                    final chip = Flexible(
                      child: FeelingChip(
                        label: strongest.feeling.label,
                        color: strongest.feeling.accent(journal),
                        intensityLabel: intensityLabel,
                      ),
                    );

                    // #141: the third instance of #137's shape -- fixed,
                    // non-flexible siblings are what overflow the row,
                    // not the trailing `Flexible` chip itself. The
                    // `Eyebrow` label and the intensity bar are both
                    // deliberately rigid (the accessibility scale the
                    // user chose, and #115's proportional-gauge contract,
                    // respectively), so -- exactly like #137 -- the
                    // question this measures is only "does everything
                    // that *cannot* shrink actually fit *this* row, right
                    // now", never a hardcoded width-or-scale threshold.
                    //
                    // The chip is not entirely exempt from that sum,
                    // though: its own label wraps freely inside its
                    // `Flexible` (#111), so it truly can go to zero
                    // width, but its *intensity suffix* -- "4/5 +1" --
                    // is a plain, un-`Flexible` `Text` next to it (never
                    // shrinks, never wraps, by the same anti-truncation
                    // rule that keeps every number on this card whole),
                    // and the dot, its own gaps, padding and border
                    // around all of it don't shrink either. Leaving the
                    // chip's floor out of this sum was tried first and
                    // measured wrong: a fixture with a two-name tie
                    // ("Grateful", "4/5 +1") overflows by 54px at 320dp
                    // at the *default* text scale alone, nowhere near
                    // 2x, and by 19px even for the shortest single-name,
                    // untied case -- both well inside the "ordinary"
                    // bucket a threshold on the eyebrow and bar alone
                    // would have called safe. The chip's own padding,
                    // border and dot mirror `FeelingChip`'s build
                    // (journal/feeling_chips.dart) rather than reading
                    // them from it -- reading, not touching, its
                    // contract (#111 still owns that).
                    final eyebrowWidth = _measure(
                      JournalType.eyebrowCase('Strongest'),
                      JournalType.eyebrow,
                      MediaQuery.textScalerOf(context),
                    );
                    final intensityWidth = _measure(
                      intensityLabel,
                      theme.textTheme.labelSmall,
                      MediaQuery.textScalerOf(context),
                    );
                    final chipFloor =
                        _feelingDotSize +
                        JournalSpacing.x2 + // dot -> label gap
                        JournalSpacing.x2 + // label -> suffix gap
                        intensityWidth +
                        JournalSpacing.x4 * 2 + // Container's own padding
                        2; // the chip's 1px border, both sides
                    final nonFlexibleWidth =
                        eyebrowWidth +
                        JournalSpacing.x3 +
                        _intensityBarWidth +
                        JournalSpacing.x2 +
                        chipFloor;

                    if (nonFlexibleWidth <= constraints.maxWidth) {
                      // Ordinary case, unchanged from before this ticket:
                      // eyebrow, bar and chip share one line, the chip's
                      // own `Flexible` taking whatever is left.
                      return Row(
                        children: [
                          const Eyebrow('Strongest'),
                          const SizedBox(width: JournalSpacing.x3),
                          bar,
                          const SizedBox(width: JournalSpacing.x2),
                          chip,
                        ],
                      );
                    }

                    // Compound case: the eyebrow, the bar and the chip's
                    // own floor do not fit *together*, so no split of
                    // leftover space could ever have saved this line --
                    // the same reasoning #137 used once the fixed side
                    // alone already lost. Shrinking the eyebrow's type
                    // fights the accessibility scale the user just asked
                    // for (the same rule that ruled out shrinking the
                    // count/label pair in #137), and the bar's 60x4 is
                    // #115's own proportional-gauge contract, not this
                    // row's to change. That leaves the third option named
                    // in the issue: the eyebrow moves to a line of its
                    // own, and the bar keeps its place directly beside the
                    // chip it is gauging -- rather than, say, isolating the
                    // bar alone, which would strand it with nothing to
                    // read against. The eyebrow alone is comfortably
                    // narrower than every width this card is asked to
                    // render at, so it never needs this same treatment
                    // recursively; the bar and the chip's floor together
                    // are smaller still.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Strongest'),
                        const SizedBox(height: JournalSpacing.x2),
                        Row(
                          children: [
                            bar,
                            const SizedBox(width: JournalSpacing.x2),
                            chip,
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The width [text] would render at in [style] under [scaler], as a single
/// unwrapped line -- what a `TextPainter` computes is the same measurement
/// Flutter's own text layout uses to paint it, so this asks the count/span
/// row's build-time question directly ("does the pair fit *this* row,
/// right now") instead of a hardcoded digit-count-or-scale threshold (#137).
double _measure(String text, TextStyle? style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();
  return painter.width;
}

List<Feeling> _distinctFeelings(List<Entry> entries) {
  final seen = <String>{};
  final result = <Feeling>[];
  for (final entry in entries) {
    for (final feeling in entry.feelings) {
      if (seen.add(feeling.key)) result.add(feeling);
    }
  }
  return result;
}

/// The feeling that reached the day's strongest rating, first by day order,
/// plus how many others tied it.
class const _Strongest(final Feeling feeling, final int tiedCount);

/// Finds which feeling(s) on [entries] reached [intensity] -- the day's own
/// maximum, as already reported by the backend roll-up.
///
/// [entries] arrive from the backend in day order (`ORDER BY created_at`),
/// and each feeling is read in the order it was chosen on its entry, so
/// walking them in place is walking the day in order; a feeling rated on
/// more than one entry is judged by its own highest rating, and counted
/// once. Several feelings can tie for the maximum -- the first one seen
/// becomes [_Strongest.feeling] and the rest are folded into
/// [_Strongest.tiedCount]. Returns null when no entry accounts for
/// [intensity] at all.
_Strongest? _strongestFeeling(List<Entry> entries, int intensity) {
  final order = <String>[];
  final byKey = <String, Feeling>{};
  final maxByKey = <String, int>{};
  for (final entry in entries) {
    for (final feeling in entry.feelings) {
      final rating = entry.feelingIntensities[feeling.key];
      if (rating == null) continue;
      if (!byKey.containsKey(feeling.key)) {
        order.add(feeling.key);
        byKey[feeling.key] = feeling;
      }
      final current = maxByKey[feeling.key];
      if (current == null || rating > current) maxByKey[feeling.key] = rating;
    }
  }
  final atMax = [
    for (final key in order)
      if (maxByKey[key] == intensity) byKey[key]!,
  ];
  return atMax.isEmpty ? null : _Strongest(atMax.first, atMax.length - 1);
}

/// "7:15 AM – 10:40 PM" in the locale's short time format, or "at 7:15 AM"
/// for a single entry (or several written in the same minute).
String? _timeSpan(int count, DateTime? first, DateTime? last) {
  if (first == null || last == null) return null;
  final format = DateFormat.jm();
  if (count == 1 || first == last) return 'at ${format.format(first)}';
  return '${format.format(first)} – ${format.format(last)}';
}

/// The calendar cell's rating bar, at reading size, so the two screens
/// agree on sight.
///
/// **Not a `Stack`.** A `Stack`'s non-positioned children get *loose*
/// constraints by default (`StackFit.loose`): a bare [DecoratedBox] — no
/// child of its own — then sizes to the smallest box the constraints
/// allow, which is zero. That is exactly what made this bar (and the
/// calendar's own copy of it) invisible from the day either shipped
/// (#108, #115): the widget tree was correct, `widthFactor` was correct,
/// and the painted bar was a zero-by-zero rectangle. A [DecoratedBox]
/// track holding an [Align]ed, explicitly-sized [FractionallySizedBox]
/// says directly what this is — a track with a proportional fill — and
/// does not depend on which fit mode a future edit might change.
/// `heightFactor: 1` is required despite the track already being 4px
/// tall: [Align] always loosens the constraints it hands to its child
/// (`constraints.loosen()` in `RenderPositionedBox`), so a null
/// `heightFactor` would reintroduce the exact same zero-height trap this
/// comment is warning about. See `calendar_screen.dart`'s `_VolumeBar` for
/// the original writeup of this trap.
class _IntensityBar extends StatelessWidget {
  const _IntensityBar({super.key, required this.intensity});

  final int intensity;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    final theme = Theme.of(context);
    return SizedBox(
      width: _intensityBarWidth,
      height: 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: journal.hairline,
          borderRadius: JournalShapes.full,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (intensity / _barMaxIntensity).clamp(0, 1),
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: JournalShapes.full,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
