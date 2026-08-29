import 'package:flutter/material.dart';

import '../../core/diary/pattern.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/journal_dashed_border.dart';

/// "When am I worst?", answered from entries the user already wrote.
///
/// Two rules shape everything here, and both come from the backend rather
/// than from this file:
///
///  - **A thin bucket says so.** One Monday is an anecdote. The backend
///    marks a bucket insufficient and sends no average at all, and this
///    panel draws a hollow marker centered on the axis rather than a
///    coloured one at zero, which would read as a perfectly average
///    Monday.
///  - **These are time patterns, not causes.** Nothing here says a weekday
///    *makes* anyone feel anything. It says what the diary contains.
///
/// Every row shares one −1…+1 axis so a marker can be read against its
/// neighbours, not just against its own row. The only computation this
/// screen performs anywhere is presentation: mapping the backend's average
/// onto that axis, and reading its sign to pick a colour and a track
/// position. The wording never rounds the number into a judgement word
/// ("slightly low", "very positive") the backend did not send — the exact
/// average is always printed, labelled, next to the count.
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
            const SizedBox(height: JournalSpacing.x4),
            _WhenChart(
              // One family per bucket kind. Ticket CH-5 plans to add an
              // hourly family here -- everything below this list (the
              // axis, the shared zero rule, the row and marker widgets) is
              // written to take any number of families rather than
              // assuming exactly two, so that ticket is a third list entry,
              // not a rewrite.
              families: [
                _WhenRowFamily(
                  title: 'By day of the week',
                  buckets: insights.weekdays,
                  best: insights.bestWeekday,
                  worst: insights.worstWeekday,
                ),
                _WhenRowFamily(
                  title: 'By time of day',
                  buckets: insights.timesOfDay,
                  best: insights.bestTimeOfDay,
                  worst: insights.worstTimeOfDay,
                ),
              ],
              minimum: insights.minBucketEntries,
            ),
          ],
        ],
      ),
    );
  }
}

/// The width every row's label column, and the axis's leading spacer,
/// share -- so a track never starts at a different x than its neighbour's
/// and the axis lines up under all of them at once.
const double _labelColumnWidth = 104;

/// One row-family in the shared chart: a heading plus the buckets under it.
/// Not a domain type -- just the pairing of a title with the three fields
/// [_WhenRow] needs, kept out of [WhenInsights] because "how many families
/// and what each is called" is this screen's business, not the backend's.
class _WhenRowFamily {
  const _WhenRowFamily({
    required this.title,
    required this.buckets,
    required this.best,
    required this.worst,
  });

  final String title;
  final List<WhenBucket> buckets;
  final String? best;
  final String? worst;
}

/// One shared −1…+1 axis, the light zero rule that threads through every
/// row of every family, and the families themselves.
///
/// The axis and the rule are drawn once for the whole chart rather than
/// once per family: a reader compares Monday against Friday and morning
/// against night on the same scale, so the scale itself has to appear only
/// once.
class _WhenChart extends StatelessWidget {
  const _WhenChart({required this.families, required this.minimum});

  final List<_WhenRowFamily> families;
  final int minimum;

  bool get _hasSuppressed => families.any(
    (family) => family.buckets.any(
      (bucket) => !(bucket.sufficient && bucket.averageValence != null),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journal = context.journalColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WhenAxis(),
        const SizedBox(height: JournalSpacing.x1),
        LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth =
                (constraints.maxWidth - _labelColumnWidth - JournalSpacing.x3)
                    .clamp(0.0, double.infinity);
            final zeroX =
                _labelColumnWidth + JournalSpacing.x3 + trackWidth / 2;
            return Stack(
              children: [
                // The rule itself. `Positioned` with both `top` and
                // `bottom` set gives its child a tight height equal to
                // everything below the axis, so a plain coloured box
                // fills exactly that height regardless of how tall the
                // families below happen to be.
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: zeroX - 0.5,
                  width: 1,
                  child: ColoredBox(color: journal.hairline),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < families.length; i++) ...[
                      if (i > 0) const SizedBox(height: JournalSpacing.x4),
                      Text(
                        families[i].title,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: JournalSpacing.x2),
                      for (final bucket in families[i].buckets) ...[
                        _WhenRow(
                          bucket: bucket,
                          isBest: bucket.key == families[i].best,
                          isWorst: bucket.key == families[i].worst,
                          minimum: minimum,
                        ),
                        const SizedBox(height: JournalSpacing.x3),
                      ],
                    ],
                    // One legend for the whole chart, not one apology per
                    // suppressed row -- see the panel's own doc comment.
                    if (_hasSuppressed) _SuppressedLegend(minimum: minimum),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The −1, 0, +1 tick labels, aligned over every row's track.
class _WhenAxis extends StatelessWidget {
  const _WhenAxis();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return ExcludeSemantics(
      // Decorative: every row already states its own value in words, so a
      // screen reader repeating "minus one, zero, plus one" here would be
      // noise rather than information.
      child: Row(
        children: [
          const SizedBox(width: _labelColumnWidth + JournalSpacing.x3),
          Expanded(
            child: Row(
              children: [
                Expanded(child: Text('-1', style: style)),
                Expanded(
                  child: Text('0', style: style, textAlign: TextAlign.center),
                ),
                Expanded(
                  child: Text('+1', style: style, textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One weekday or time-of-day row: the label, the shared track with its
/// marker, and -- for a sufficient bucket -- the exact average and count in
/// one labelled line underneath.
class _WhenRow extends StatelessWidget {
  const _WhenRow({
    required this.bucket,
    required this.isBest,
    required this.isWorst,
    required this.minimum,
  });

  final WhenBucket bucket;
  final bool isBest;
  final bool isWorst;
  final int minimum;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journal = context.journalColors;
    final average = bucket.averageValence;
    final isSufficient = bucket.sufficient && average != null;
    final entryWord = bucket.entryCount == 1 ? 'entry' : 'entries';
    final statusSuffix = isBest
        ? ', the best in this window'
        : isWorst
        ? ', the hardest in this window'
        : '';

    final semanticsLabel = isSufficient
        ? '${bucket.label}: average valence '
              '${average >= 0 ? '+' : ''}${average.toStringAsFixed(2)} from '
              '${bucket.entryCount} $entryWord$statusSuffix'
        : '${bucket.label}: fewer than $minimum entries, not enough to '
              'show$statusSuffix';

    return Semantics(
      label: semanticsLabel,
      container: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // The label column is fixed so every track starts at the
                // same x -- a row whose track begins further left than its
                // neighbour's cannot be read against them, which is the
                // only thing this panel is for. The badge sits below the
                // name rather than beside it: sharing the width squeezed
                // "HARDEST" into whatever the weekday name left over and
                // wrapped it mid-word.
                SizedBox(
                  width: _labelColumnWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bucket.label, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: JournalSpacing.x1),
                      // Named in words as well as marked, so the highlight
                      // survives greyscale. Wrapped in a `FittedBox` rather
                      // than trusting the label column outright -- the
                      // width is tuned against Compose's own font metrics,
                      // and this keeps "Hardest" from ever clipping under a
                      // wider system font or a larger text scale instead of
                      // re-tuning a pixel constant per platform.
                      if (isBest)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: StatusBadge(
                            'Best',
                            contentColor: journal.success,
                            containerColor: journal.successContainer,
                          ),
                        )
                      else if (isWorst)
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
                  child: _Track(average: average, sufficient: isSufficient),
                ),
              ],
            ),
            if (isSufficient) ...[
              const SizedBox(height: JournalSpacing.x1),
              Padding(
                padding: const EdgeInsets.only(
                  left: _labelColumnWidth + JournalSpacing.x3,
                ),
                child: Text(
                  'average valence ${average >= 0 ? '+' : ''}'
                  '${average.toStringAsFixed(2)} · ${bucket.entryCount} '
                  '$entryWord',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A track with a marker, not a bar: the scale runs from -1 to +1, and a
/// bar growing from the left would read as "more" when what is meant is
/// "further one way".
///
/// A sufficient bucket draws a filled circle, coloured by the sign of
/// [average] alone -- never by its magnitude, which would mean this widget
/// deciding what counts as "slightly" or "very" low, a judgement the
/// backend has not made. An insufficient bucket ([sufficient] false) draws
/// a hollow, dashed circle centred on the axis instead: present enough to
/// show the bucket exists, empty enough that it is never mistaken for a
/// measured zero.
class _Track extends StatelessWidget {
  const _Track({required this.average, required this.sufficient});

  final double? average;
  final bool sufficient;

  static const double _trackHeight = 20;
  static const double _markerSize = 14;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    final theme = Theme.of(context);
    final resolvedAverage = average ?? 0;
    final fraction = sufficient
        ? ((resolvedAverage + 1) / 2).clamp(0.0, 1.0)
        : 0.5;
    final color = !sufficient
        ? theme.colorScheme.onSurfaceVariant
        : resolvedAverage > 0
        ? journal.feelings.uplifted
        : resolvedAverage < 0
        ? journal.feelings.low
        : journal.feelings.steady;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackAvail = (constraints.maxWidth - _markerSize).clamp(
          0.0,
          double.infinity,
        );
        final left = trackAvail * fraction;
        return SizedBox(
          height: _trackHeight,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: JournalShapes.full,
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: left,
                  top: (_trackHeight - _markerSize) / 2,
                  child: sufficient
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                          ),
                          child: const SizedBox(
                            width: _markerSize,
                            height: _markerSize,
                          ),
                        )
                      : DashedBorder(
                          color: color,
                          borderRadius: JournalShapes.full,
                          strokeWidth: 1.5,
                          dash: 3,
                          gap: 2,
                          child: const SizedBox(
                            width: _markerSize,
                            height: _markerSize,
                          ),
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

/// The single legend line for every hollow marker in the chart, shown once
/// at the bottom rather than as a repeated apology on each thin row.
class _SuppressedLegend extends StatelessWidget {
  const _SuppressedLegend({required this.minimum});

  final int minimum;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: JournalSpacing.x1),
      child: Text(
        '○ fewer than $minimum entries — not enough to show',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
