import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
              Row(
                // Keyed so `day_summary_card_test.dart` can measure this
                // row's own rendered width directly (#131) -- the same
                // reason `_IntensityBar` picked up a key for #115: a test
                // that only finds widgets by type risks matching the wrong
                // `Row` once the card has more than one.
                key: const ValueKey('daySummaryCountSpanRow'),
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$count',
                    style: JournalType.tabularFigures(
                      theme.textTheme.displaySmall!,
                    ).copyWith(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: JournalSpacing.x2),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      count == 1 ? 'entry' : 'entries',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: journal.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // #131: this used to be a `Spacer()` plus a plain `Text`,
                  // which gave the span unbounded width to lay out with --
                  // the same defect family as #111/#117, except a `Row`
                  // announces it as a `RenderFlex` overflow instead of
                  // silently mis-sizing. The count is the fixed-ish side
                  // (a digit plus "entry"/"entries" never grows past two
                  // short words), so it stays un-flexible and the span --
                  // the side whose width actually varies with the day's
                  // data -- is what yields. `Expanded` (not `Flexible`)
                  // is required to still hug the row's trailing edge when
                  // there is room: a bare `Flexible` does not claim the
                  // leftover main-axis space the way `Spacer` used to, so
                  // the span would sit immediately after the count instead
                  // of at the right. It wraps to a second line rather than
                  // truncating -- the product rule against clipping a
                  // number applies to the span's clock times as much as it
                  // does to the entry count.
                  if (spanText != null)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          spanText,
                          textAlign: TextAlign.right,
                          style: JournalType.tabularFigures(
                            theme.textTheme.bodySmall!,
                          ).copyWith(color: journal.onSurfaceVariant),
                        ),
                      ),
                    ),
                ],
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
                Row(
                  children: [
                    const Eyebrow('Strongest'),
                    const SizedBox(width: JournalSpacing.x3),
                    _IntensityBar(
                      key: const ValueKey('daySummaryIntensityBar'),
                      intensity: intensity!,
                    ),
                    const SizedBox(width: JournalSpacing.x2),
                    Flexible(
                      child: FeelingChip(
                        label: strongest.feeling.label,
                        color: strongest.feeling.accent(journal),
                        intensityLabel: strongest.tiedCount > 0
                            ? '$intensity/5 +${strongest.tiedCount}'
                            : '$intensity/5',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
      width: 60,
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
