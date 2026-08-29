import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/diary/entry.dart';
import '../../core/diary/feeling.dart';
import '../../core/diary/monthly_summary.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/theme/journal_typography.dart';
import '../../core/widgets/feeling_accent.dart';
import '../../core/widgets/feeling_chips.dart';
import '../../core/widgets/journal.dart';

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
    final times = [
      for (final entry in entries) entry.createdAt.toLocal(),
    ]..sort();
    final first = times.isEmpty ? null : times.first;
    final last = times.isEmpty ? null : times.last;
    final feelings = (summary?.feelings.isNotEmpty ?? false)
        ? summary!.feelings
        : _distinctFeelings(entries);
    final intensity = summary?.intensity;

    final spanText = _timeSpan(count, first, last);
    final countText = count == 1 ? '1 entry' : '$count entries';

    final spoken = StringBuffer(isToday ? 'The day so far. ' : 'The day. ')
      ..write(countText);
    if (spanText != null) spoken.write(', $spanText');
    if (feelings.isNotEmpty) {
      spoken.write('. ${feelings.map((f) => f.label).join(', ')}');
    }
    if (intensity != null) spoken.write('. Strongest $intensity of 5');

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
                  if (spanText != null) ...[
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        spanText,
                        style: JournalType.tabularFigures(
                          theme.textTheme.bodySmall!,
                        ).copyWith(color: journal.onSurfaceVariant),
                      ),
                    ),
                  ],
                ],
              ),
              if (feelings.isNotEmpty || intensity != null) ...[
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
              if (intensity != null) ...[
                const SizedBox(height: JournalSpacing.x3),
                Row(
                  children: [
                    const Eyebrow('Strongest'),
                    const SizedBox(width: JournalSpacing.x3),
                    _IntensityBar(intensity: intensity),
                    const SizedBox(width: JournalSpacing.x2),
                    Text(
                      '$intensity of 5',
                      style: JournalType.tabularFigures(
                        theme.textTheme.bodySmall!,
                      ).copyWith(color: journal.onSurfaceVariant),
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
class _IntensityBar extends StatelessWidget {
  const _IntensityBar({required this.intensity});

  final int intensity;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    final theme = Theme.of(context);
    return SizedBox(
      width: 60,
      height: 4,
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: journal.hairline,
              borderRadius: JournalShapes.full,
            ),
          ),
          FractionallySizedBox(
            widthFactor: (intensity / 5).clamp(0, 1),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: JournalShapes.full,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
