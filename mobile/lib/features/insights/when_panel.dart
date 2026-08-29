import 'package:flutter/material.dart';

import '../../core/diary/pattern.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';

/// "When am I worst?", answered from entries the user already wrote.
///
/// Two rules shape everything here, and both come from the backend rather
/// than from this file:
///
///  - **A thin bucket says so.** One Monday is an anecdote. The backend
///    marks a bucket insufficient and sends no average at all, and this
///    panel prints "fewer than N entries" rather than drawing a marker at
///    zero, which would read as a perfectly average Monday.
///  - **These are time patterns, not causes.** Nothing here says a weekday
///    *makes* anyone feel anything. It says what the diary contains.
///
/// The marker's position is the only computation this screen performs
/// anywhere, and it is presentation: mapping a -1..+1 average the backend
/// produced onto a track.
class WhenPanel extends StatelessWidget {
  /// Builds the panel from [insights].
  const WhenPanel({super.key, required this.insights});

  /// The weekday and time-of-day breakdown to show.
  final WhenInsights insights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('When it happens', style: theme.textTheme.titleLarge),
          const SizedBox(height: JournalSpacing.x2),
          if (insights.totalEntries == 0)
            Text(
              'Nothing in the last ${insights.windowDays} days yet — this '
              'fills in as you write.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            Text(
              'Across the ${insights.totalEntries} '
              '${insights.totalEntries == 1 ? 'entry' : 'entries'} you '
              'confirmed in the last ${insights.windowDays} days. These are '
              'times, not causes.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            _WhenGroup(
              title: 'By day of the week',
              buckets: insights.weekdays,
              best: insights.bestWeekday,
              worst: insights.worstWeekday,
              minimum: insights.minBucketEntries,
            ),
            _WhenGroup(
              title: 'By time of day',
              buckets: insights.timesOfDay,
              best: insights.bestTimeOfDay,
              worst: insights.worstTimeOfDay,
              minimum: insights.minBucketEntries,
            ),
          ],
        ],
      ),
    );
  }
}

class _WhenGroup extends StatelessWidget {
  const _WhenGroup({
    required this.title,
    required this.buckets,
    required this.best,
    required this.worst,
    required this.minimum,
  });

  final String title;
  final List<WhenBucket> buckets;
  final String? best;
  final String? worst;
  final int minimum;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: JournalSpacing.x4),
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: JournalSpacing.x2),
        for (final bucket in buckets) ...[
          _WhenRow(bucket: bucket, best: best, worst: worst, minimum: minimum),
          const SizedBox(height: JournalSpacing.x2),
        ],
      ],
    );
  }
}

class _WhenRow extends StatelessWidget {
  const _WhenRow({
    required this.bucket,
    required this.best,
    required this.worst,
    required this.minimum,
  });

  final WhenBucket bucket;
  final String? best;
  final String? worst;
  final int minimum;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journal = context.journalColors;
    final average = bucket.averageValence;
    final isSufficient = bucket.sufficient && average != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // The label column is fixed so every track starts at the same x --
        // a row whose bar begins further left than its neighbour's cannot
        // be read against them, which is the only thing this panel is for.
        // The badge sits below the name rather than beside it: sharing the
        // width squeezed "HARDEST" into whatever the weekday name left
        // over and wrapped it mid-word.
        SizedBox(
          width: 104,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bucket.label, style: theme.textTheme.bodyMedium),
              const SizedBox(height: JournalSpacing.x1),
              // Named in words as well as marked, so the highlight survives
              // greyscale. Wrapped in a `FittedBox` rather than trusting the
              // 104dp column outright -- the label width is a port of a
              // value tuned against Compose's own font metrics, and this
              // keeps "Hardest" from ever clipping under a wider system
              // font instead of re-tuning a pixel constant per platform.
              if (bucket.key == best)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(
                    'Best',
                    contentColor: journal.success,
                    containerColor: journal.successContainer,
                  ),
                )
              else if (bucket.key == worst)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(
                    'Hardest',
                    contentColor: theme.colorScheme.onErrorContainer,
                    containerColor: theme.colorScheme.errorContainer,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: JournalSpacing.x3),
        Expanded(
          child: isSufficient
              ? _Track(average: average)
              : Text(
                  'fewer than $minimum entries',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(width: JournalSpacing.x3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isSufficient)
              Text(
                '${average >= 0 ? '+' : ''}${average.toStringAsFixed(2)}',
                style: theme.textTheme.labelSmall,
              ),
            Eyebrow('${bucket.entryCount}'),
          ],
        ),
      ],
    );
  }
}

/// A track with a marker, not a bar: the scale runs from -1 to +1, and a bar
/// growing from the left would read as "more" when what is meant is
/// "further one way".
class _Track extends StatelessWidget {
  const _Track({required this.average});

  final double average;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    final theme = Theme.of(context);
    final fraction = ((average + 1) / 2).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 10,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: JournalShapes.full,
            ),
            child: Stack(
              children: [
                Positioned(
                  left: width / 2,
                  child: Container(
                    width: 2,
                    height: 10,
                    color: journal.hairline,
                  ),
                ),
                Positioned(
                  left: (width - 12) * fraction,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: average < 0
                          ? theme.colorScheme.error
                          : journal.success,
                    ),
                    child: const SizedBox(width: 12, height: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
