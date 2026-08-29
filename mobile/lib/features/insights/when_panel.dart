import 'package:flutter/material.dart';

import '../../core/diary/pattern.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/theme/journal_palette.dart';
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
              // One family per bucket kind. Everything below this list (the
              // axis, the shared zero rule, the row and marker widgets) is
              // written to take any number of families rather than
              // assuming exactly two.
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
              // CH-5: the heat strip is not a fourth row-family -- it is a
              // different chart shape (twelve cells, not an axis row) -- so
              // it is threaded through separately and drawn right under the
              // "By time of day" rows above rather than appended to
              // [families]. It still shares this chart's one suppressed
              // marker legend at the bottom instead of printing its own.
              hourlyInsights: insights,
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

/// "average valence -0.27 · 15 entries" -- the exact figure and the count
/// for a sufficient bucket, in the one wording this panel ever uses for it.
///
/// Shared between [_WhenRow]'s printed line and the heat strip's tap/
/// long-press detail so the two chart shapes describe the same
/// [WhenBucket] field the same way, and so the panel never grows a second
/// place that decides how to phrase a valence average.
///
/// Only called for [WhenBucket.sufficient] buckets with a non-null
/// [WhenBucket.averageValence] -- callers gate on that themselves, the same
/// way [_WhenRow] already did before this was factored out.
String bucketDetailText(WhenBucket bucket) {
  final average = bucket.averageValence!;
  final entryWord = bucket.entryCount == 1 ? 'entry' : 'entries';
  return 'average valence ${average >= 0 ? '+' : ''}'
      '${average.toStringAsFixed(2)} · ${bucket.entryCount} $entryWord';
}

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
  const _WhenChart({
    required this.families,
    required this.minimum,
    required this.hourlyInsights,
  });

  final List<_WhenRowFamily> families;
  final int minimum;

  /// The whole payload, not just [WhenInsights.hourly] -- the heat strip's
  /// semantics label also reads [WhenInsights.timesOfDay] (for "cluster in
  /// the evening") and [WhenInsights.worstHour] (for "lowest around").
  final WhenInsights hourlyInsights;

  bool _bucketSuppressed(WhenBucket bucket) =>
      !(bucket.sufficient && bucket.averageValence != null);

  bool get _hasSuppressed =>
      families.any((family) => family.buckets.any(_bucketSuppressed)) ||
      hourlyInsights.hourly.any(_bucketSuppressed);

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
                  ],
                ),
              ],
            );
          },
        ),
        // The heat strip is not on the −1…+1 axis above -- it is a
        // different chart shape -- so it sits outside the `Stack` rather
        // than under the zero rule, which would otherwise run straight
        // through cells it has nothing to say about.
        if (hourlyInsights.hourly.isNotEmpty) ...[
          const SizedBox(height: JournalSpacing.x4),
          _HourlyStrip(insights: hourlyInsights, minimum: minimum),
        ],
        // One legend for the whole chart, not one apology per suppressed
        // row or cell -- see the panel's own doc comment.
        if (_hasSuppressed) _SuppressedLegend(minimum: minimum),
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
                  bucketDetailText(bucket),
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

/// The heat strip under "By time of day": twelve 2-hour cells, coloured by
/// mean valence on the shared ramp (CH-5, [ValenceRamp.colorForScore]).
/// Reads as part of this panel rather than a bolted-on widget: it opens
/// with the same small-heading style the two row families above it use,
/// reuses their hollow-marker suppression convention for a thin cell, and
/// leans on the chart's one shared legend line instead of printing a
/// second apology of its own.
///
/// Twelve real cell widgets, not a canvas -- unlike the calendar's year grid
/// and its 372 days, twelve is cheap enough that each cell can be its own
/// [GestureDetector] without the single-hit-test trick that grid needs.
/// Accessibility still follows that grid's shape: the strip exposes one
/// semantic node
/// summarising the whole pattern ([hourlyStripSemantics]), and a per-cell
/// detail line ([hourCellDetailText]) appears -- as its own live-announcing
/// node, and as an inline caption every sighted user sees too -- only while
/// a tap or long-press holds one cell active.
class _HourlyStrip extends StatefulWidget {
  const _HourlyStrip({required this.insights, required this.minimum});

  /// The whole payload -- the strip's own semantics read [WhenInsights.
  /// timesOfDay] and [WhenInsights.busiestTimeOfDay] as well as
  /// [WhenInsights.hourly].
  final WhenInsights insights;
  final int minimum;

  @override
  State<_HourlyStrip> createState() => _HourlyStripState();
}

class _HourlyStripState extends State<_HourlyStrip> {
  int? _activeIndex;

  /// A tap on the already-active cell closes its detail line; a tap on any
  /// other cell opens that one instead. There is never more than one open
  /// at a time -- the caption below the strip has room for exactly one.
  void _tap(int index) =>
      setState(() => _activeIndex = _activeIndex == index ? null : index);

  void _pressStart(int index) => setState(() => _activeIndex = index);

  void _pressEnd() => setState(() => _activeIndex = null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buckets = widget.insights.hourly;
    final activeIndex = _activeIndex;
    final active =
        activeIndex != null && activeIndex >= 0 && activeIndex < buckets.length
        ? buckets[activeIndex]
        : null;

    return Semantics(
      container: true,
      label: hourlyStripSemantics(widget.insights),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Text('By hour', style: theme.textTheme.titleSmall),
          ),
          const SizedBox(height: JournalSpacing.x2),
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < buckets.length; i++) ...[
                  if (i > 0) const SizedBox(width: JournalSpacing.x1 / 2),
                  Expanded(
                    child: GestureDetector(
                      key: Key('hourCell-${buckets[i].key}'),
                      onTap: () => _tap(i),
                      onLongPressStart: (_) => _pressStart(i),
                      onLongPressEnd: (_) => _pressEnd(),
                      child: _HourCell(bucket: buckets[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: JournalSpacing.x1),
          ExcludeSemantics(child: _HourAxisLabels(buckets: buckets)),
          if (active != null) ...[
            const SizedBox(height: JournalSpacing.x1),
            Semantics(
              liveRegion: true,
              label: hourCellDetailText(active, widget.minimum),
              child: ExcludeSemantics(
                child: Text(
                  hourCellDetailText(active, widget.minimum),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One 2-hour cell: filled with [ValenceRamp.colorForScore] when
/// [WhenBucket.sufficient] carries a real average, or hollow and dashed --
/// the same suppression convention [_Track] draws for a thin weekday/
/// time-of-day bucket -- when it does not.
class _HourCell extends StatelessWidget {
  const _HourCell({required this.bucket});

  final WhenBucket bucket;

  static const double _height = 28;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    final theme = Theme.of(context);
    final average = bucket.averageValence;

    if (bucket.sufficient && average != null) {
      return SizedBox(
        height: _height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: journal.feelings.colorForScore(average),
            borderRadius: JournalShapes.small,
          ),
        ),
      );
    }

    return SizedBox(
      height: _height,
      child: DashedBorder(
        color: theme.colorScheme.onSurfaceVariant,
        borderRadius: JournalShapes.small,
        strokeWidth: 1.5,
        dash: 3,
        gap: 2,
        // A transparent `ColoredBox`, not a bare `SizedBox` -- unlike the
        // sufficient branch's `DecoratedBox` above, a `CustomPaint` (which
        // `DashedBorder` draws through) does not treat its own painted
        // area as tappable by default, and neither does an empty `SizedBox`.
        // `ColoredBox` always does, transparent or not, which is what makes
        // a hollow cell -- not just a coloured one -- register the tap and
        // long-press this widget wires up on it.
        child: const ColoredBox(color: Colors.transparent),
      ),
    );
  }
}

/// The sparse 0/6/12/18 hour ticks under the strip.
///
/// Every third cell gets a tick -- indices 0, 3, 6 and 9, which are hours 0,
/// 6, 12 and 18 given the backend's fixed 2-hour block width -- and the label
/// text itself is read off each tick cell's own [WhenBucket.key] rather
/// than a hardcoded string, so a cell and the tick under it can never name
/// two different hours.
class _HourAxisLabels extends StatelessWidget {
  const _HourAxisLabels({required this.buckets});

  final List<WhenBucket> buckets;

  static const Set<int> _tickIndices = {0, 3, 6, 9};

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        for (var i = 0; i < buckets.length; i++)
          Expanded(
            child: Text(
              _tickIndices.contains(i) ? _hourLabel(buckets[i].key) : '',
              style: style,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

/// "18" from "18", "6" from "06" -- the strip's ticks drop the backend's
/// zero-padding, which exists so `key` sorts and compares cleanly but reads
/// oddly under a tick mark.
String _hourLabel(String key) => int.tryParse(key)?.toString() ?? key;

/// The heat strip's one semantics summary (I5-06's restraint again): built
/// only from fields the backend already computed -- the [WhenInsights.
/// timesOfDay] bucket with the most entries, and the [WhenInsights.
/// worstHour] bucket by average valence -- never a magnitude word this
/// screen invented on its own. Falls back to a plain "not enough entries
/// yet" sentence when neither is available (a tie, or too little written
/// so far), the same restraint the backend's own `extreme` applies to
/// [WhenInsights.bestWeekday]/[WhenInsights.worstWeekday].
String hourlyStripSemantics(WhenInsights insights) {
  final clusterBucket = insights.timesOfDay
      .where((bucket) => bucket.key == insights.busiestTimeOfDay)
      .firstOrNull;
  final worstBucket = insights.hourly
      .where((bucket) => bucket.key == insights.worstHour)
      .firstOrNull;

  final clusterClause = clusterBucket == null
      ? null
      : 'entries cluster in the ${clusterBucket.label.toLowerCase()}';
  final worstAverage = worstBucket?.averageValence;
  final worstClause = worstBucket == null || worstAverage == null
      ? null
      : 'lowest around ${worstBucket.key}:00 (from ${worstBucket.entryCount} '
            '${worstBucket.entryCount == 1 ? 'entry' : 'entries'})';

  final clauses = [clusterClause, worstClause].whereType<String>().toList();
  if (clauses.isEmpty) {
    return 'By hour: not enough entries yet to show a pattern.';
  }
  return 'By hour: ${clauses.join('; ')}.';
}

/// "18:00–20:00 · average valence -0.27 · 15 entries" for a sufficient cell
/// once tapped or long-pressed -- reusing [bucketDetailText] so a cell here
/// describes its valence in exactly the same words a row does. A
/// suppressed cell reuses the chart's one legend phrase rather than
/// inventing a second wording for the same fact.
String hourCellDetailText(WhenBucket bucket, int minimum) {
  final isSufficient = bucket.sufficient && bucket.averageValence != null;
  final detail = isSufficient
      ? bucketDetailText(bucket)
      : 'fewer than $minimum entries — not enough to show';
  return '${bucket.label} · $detail';
}
