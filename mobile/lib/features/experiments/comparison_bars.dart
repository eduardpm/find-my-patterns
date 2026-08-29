import 'package:flutter/material.dart';

import '../../core/diary/experiment.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';

/// The two-window comparison, as a pair of CH-4-style bars: how often
/// [feelingLabel] showed up in the entries that mentioned the topic, during
/// the experiment and in the baseline window before it.
///
/// CH-4 (#32) is landing a bar component for the pattern card around the
/// same time as this ticket; this widget is its own, separate
/// implementation rather than a shared one, because that ticket had not
/// merged when this one was written. A follow-up can fold the two into one
/// component once CH-4 is in -- see the PR description.
///
/// [experimentWindow] and [baselineWindow]'s own [ExperimentWindow.presentRate]
/// is what each bar fills to; nothing here recomputes a rate from a count.
/// A `null` rate -- fewer than [ExperimentConstants.minBucketEntries]
/// mentions of the topic -- draws an empty bar with an em dash, never a
/// invented `0%`, matching every other undefined rate in this app.
class ComparisonBars extends StatelessWidget {
  /// Builds the bars for [experimentWindow] and [baselineWindow].
  const ComparisonBars({
    super.key,
    required this.experimentWindow,
    required this.baselineWindow,
    required this.feelingLabel,
  });

  /// The "during" window.
  final ExperimentWindow experimentWindow;

  /// The "before" baseline window, the same length as [experimentWindow].
  final ExperimentWindow baselineWindow;

  /// The feeling both bars measure the rate of.
  final String feelingLabel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _ComparisonBar(
        label: 'During the experiment',
        window: experimentWindow,
        feelingLabel: feelingLabel,
      ),
      const SizedBox(height: JournalSpacing.x3),
      _ComparisonBar(
        label: 'Before the experiment',
        window: baselineWindow,
        feelingLabel: feelingLabel,
      ),
    ],
  );
}

class _ComparisonBar extends StatelessWidget {
  const _ComparisonBar({
    required this.label,
    required this.window,
    required this.feelingLabel,
  });

  final String label;
  final ExperimentWindow window;
  final String feelingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journal = context.journalColors;
    final rate = window.presentRate;
    final percentText = rate == null ? '—' : '${(rate * 100).round()}%';
    final countText =
        '${window.presentCount}/${window.presentTotal} entries with $feelingLabel';
    return Semantics(
      label:
          '$label: $feelingLabel appeared in ${window.presentCount} of '
          '${window.presentTotal} entries mentioning the topic'
          '${rate == null ? '' : ' ($percentText)'}, over '
          '${window.totalDays} days.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Eyebrow(label)),
                Text(
                  percentText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: JournalSpacing.x1),
            ClipRRect(
              borderRadius: JournalShapes.small,
              child: LinearProgressIndicator(
                // `null` would read to `LinearProgressIndicator` as
                // "indeterminate" and animate forever, which is not what an
                // undefined rate means -- there is nothing still loading,
                // there is simply no rate to show, so the bar sits empty
                // instead. The percentage text above stays an em dash
                // either way (never an invented `0%`); only the bar's fill
                // is affected, and Article 3 puts no test on that.
                value: rate ?? 0,
                minHeight: 10,
                backgroundColor: journal.surfaceVariant,
                valueColor: AlwaysStoppedAnimation(journal.accent),
              ),
            ),
            const SizedBox(height: JournalSpacing.x1),
            Text(
              countText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: journal.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
