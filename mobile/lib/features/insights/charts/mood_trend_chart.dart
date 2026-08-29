/// CH-1: the mood-over-time line chart at the top of Insights.
///
/// Hand-drawn with [CustomPainter] rather than a charting package -- see
/// `specs/research/daylio-competitive-analysis.md` §9.1 chart 1 for the
/// stack decision. Everything this widget draws comes from
/// `GET /insights/series` (`InsightsApi.series`); it computes nothing the
/// backend did not already compute, beyond the purely presentational
/// choices of where a pixel lands and which day a drag is nearest to.
///
/// @docImport '../../../core/diary/insights_api.dart';
/// @docImport '../insights_controller.dart';
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/diary/calendar_date.dart';
import '../../../core/diary/diary_providers.dart';
import '../../../core/diary/mood_series.dart';
import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/journal_metrics.dart';
import '../../../core/widgets/journal.dart';
import '../../../core/widgets/status_views.dart';

/// The date span the switcher above the chart offers.
///
/// Every span fits inside `GET /insights/series`'s day-granularity range
/// cap (400 days), so the chart always asks for day granularity -- see
/// [InsightsApi.series].
enum MoodTrendPeriod {
  /// The last 30 days, this chart's default.
  days30(days: 30, label: '30 days', summaryLabel: 'the last 30 days'),

  /// The last 90 days.
  days90(days: 90, label: '90 days', summaryLabel: 'the last 90 days'),

  /// The last calendar year.
  year(days: 365, label: 'Year', summaryLabel: 'the last year');

  const MoodTrendPeriod({
    required this.days,
    required this.label,
    required this.summaryLabel,
  });

  /// How many days back from today this period reaches, today included.
  final int days;

  /// The segmented control's label for this period.
  final String label;

  /// How this period reads inside the accessibility summary sentence, e.g.
  /// "the last 30 days".
  final String summaryLabel;
}

/// The clock [MoodTrendController] resolves "today" on.
///
/// Defaults to the real clock; a test overrides it to pin "today" the same
/// way `dayEntriesNowProvider` does for the calendar.
final moodTrendNowProvider = Provider<DateTime?>((ref) => null);

/// The period currently selected on the mood-trend chart.
class MoodTrendPeriodController extends Notifier<MoodTrendPeriod> {
  @override
  MoodTrendPeriod build() => MoodTrendPeriod.days30;

  /// Selects [period]. [MoodTrendController.build] watches this provider,
  /// so selecting a new period is what triggers its refetch.
  void select(MoodTrendPeriod period) => state = period;
}

/// The period currently selected on the mood-trend chart.
final moodTrendPeriodProvider =
    NotifierProvider<MoodTrendPeriodController, MoodTrendPeriod>(
      MoodTrendPeriodController.new,
    );

/// Holds the mood-trend chart's own data, independent of the rest of
/// Insights.
///
/// A separate provider from [InsightsController] on purpose: the chart has
/// its own fetch (`GET /insights/series`, a pure read) and its own refetch
/// trigger (a period switch, via [moodTrendPeriodProvider]), neither of
/// which has anything to do with the patterns `GET /insights` recomputes.
class MoodTrendController extends AsyncNotifier<MoodSeries> {
  @override
  Future<MoodSeries> build() async {
    final period = ref.watch(moodTrendPeriodProvider);
    final api = ref.watch(insightsApiProvider);
    final today = CalendarDate.today(now: ref.watch(moodTrendNowProvider));
    final from = today.addDays(-(period.days - 1));
    return api.series(from: from, to: today);
  }

  /// Retries the current period's fetch, e.g. from the error state's Retry
  /// button. See [InsightsController.refresh] for why this swallows
  /// [ApiError]: the failure is already reflected in [state], and this
  /// notifier has no snack bar of its own to report it through.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } on ApiError {
      // Already reflected in `state`.
    }
  }
}

/// Holds the mood-trend chart's own data.
final moodTrendControllerProvider =
    AsyncNotifierProvider<MoodTrendController, MoodSeries>(
      MoodTrendController.new,
    );

/// A day counts toward the chart once it has a scored day; below this many,
/// there is not enough of a line to draw.
const int _minScoredDays = 3;

/// The chart canvas's fixed height, axis included.
const double _chartHeight = 160;

/// The mood-over-time chart: one point per day, a period switcher, a scrub
/// tooltip, and the states around all three (loading, error, empty).
///
/// Placed at the top of the Insights screen, above the withdrawal notices --
/// see `insights_screen.dart`.
class MoodTrendChart extends ConsumerWidget {
  /// Creates the mood-trend chart.
  const MoodTrendChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(moodTrendPeriodProvider);
    final async = ref.watch(moodTrendControllerProvider);
    final series = async.value;
    final theme = Theme.of(context);

    // Resolved once here, from the same injectable clock
    // `MoodTrendController.build` reads, so the range the chart lays out on
    // screen can never disagree with the range it fetched.
    final today = CalendarDate.today(now: ref.watch(moodTrendNowProvider));
    final from = today.addDays(-(period.days - 1));

    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mood over time', style: theme.textTheme.titleLarge),
          const SizedBox(height: JournalSpacing.x3),
          _PeriodSwitcher(
            selected: period,
            onChanged: (next) =>
                ref.read(moodTrendPeriodProvider.notifier).select(next),
          ),
          const SizedBox(height: JournalSpacing.x4),
          if (series == null)
            if (async.error case final ApiError error)
              _ChartError(
                message: _messageFor(error),
                onRetry: () => unawaited(
                  ref.read(moodTrendControllerProvider.notifier).refresh(),
                ),
              )
            else
              const _ChartSkeleton()
          else
            _ChartContent(
              period: period,
              series: series,
              from: from,
              to: today,
            ),
        ],
      ),
    );
  }
}

/// The 30/90/year segmented control. Every segment is at least
/// [JournalSpacing.x7] tall, the app's touch-target floor.
class _PeriodSwitcher extends StatelessWidget {
  const _PeriodSwitcher({required this.selected, required this.onChanged});

  final MoodTrendPeriod selected;
  final ValueChanged<MoodTrendPeriod> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<MoodTrendPeriod>(
    segments: [
      for (final period in MoodTrendPeriod.values)
        ButtonSegment(value: period, label: Text(period.label)),
    ],
    selected: {selected},
    showSelectedIcon: false,
    style: SegmentedButton.styleFrom(
      minimumSize: const Size(0, JournalSpacing.x7),
    ),
    onSelectionChanged: (next) => onChanged(next.first),
  );
}

/// The loading state: a static placeholder the size of the finished chart.
/// Deliberately not a spinner -- a chart card sitting above content that
/// already loaded should not read as broken while its own fetch is still in
/// flight.
class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.journalColors;
    return Container(
      height: _chartHeight,
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: JournalShapes.medium,
      ),
    );
  }
}

/// The error state: the shared [ErrorView].
///
/// Not sized to [_chartHeight] the way [_ChartSkeleton] is: `ErrorView`'s
/// own message-plus-Retry-button content does not reliably fit inside that
/// height, and clipping it would hide the one button this state exists to
/// offer.
class _ChartError extends StatelessWidget {
  const _ChartError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) =>
      ErrorView(message: message, onRetry: onRetry);
}

/// The empty state: fewer than [_minScoredDays] scored days in range.
class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty();

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icon(Icons.show_chart),
    title: Text('Not enough days yet — keep writing'),
  );
}

/// Data has arrived for [period]: either the empty state, or the chart
/// itself with its axis, its scrub tooltip, and its accessibility summary.
class _ChartContent extends StatelessWidget {
  const _ChartContent({
    required this.period,
    required this.series,
    required this.from,
    required this.to,
  });

  final MoodTrendPeriod period;
  final MoodSeries series;
  final CalendarDate from;
  final CalendarDate to;

  List<MoodSeriesPoint> get _scored => [
    for (final point in series.points)
      if (point.score != null) point,
  ];

  @override
  Widget build(BuildContext context) {
    final scored = _scored;
    if (scored.length < _minScoredDays) return const _ChartEmpty();

    final summary = _buildSummary(period, series.points, scored);

    // `ExcludeSemantics` hides the chart's own nodes -- the axis labels,
    // the scrub tooltip's text, the drag gesture -- so the one thing a
    // screen reader announces here is the deterministic summary sentence,
    // not that plus a scramble of merged-in chart chrome. The same
    // reasoning as `Eyebrow`'s own `Semantics`-over-`ExcludeSemantics` pair.
    return Semantics(
      container: true,
      label: summary,
      child: ExcludeSemantics(
        child: _ChartCanvas(points: series.points, from: from, to: to),
      ),
    );
  }
}

/// The interactive part: the −1/0/+1 axis, the line-and-points canvas, and
/// the scrub tooltip a tap or a drag reveals.
class _ChartCanvas extends StatefulWidget {
  const _ChartCanvas({
    required this.points,
    required this.from,
    required this.to,
  });

  final List<MoodSeriesPoint> points;
  final CalendarDate from;
  final CalendarDate to;

  @override
  State<_ChartCanvas> createState() => _ChartCanvasState();
}

class _ChartCanvasState extends State<_ChartCanvas> {
  MoodSeriesPoint? _scrubbed;

  int get _totalDays => _daysBetween(widget.from, widget.to) + 1;

  void _scrubAt(double dx, double width) {
    if (widget.points.isEmpty || width <= 0) return;
    final span = (_totalDays - 1).clamp(1, _totalDays);
    final fraction = (dx / width).clamp(0.0, 1.0);
    final dayOffset = (fraction * span).round();
    final target = widget.from.addDays(dayOffset);

    var nearest = widget.points.first;
    var nearestGap = _daysBetween(nearest.date, target).abs();
    for (final point in widget.points.skip(1)) {
      final gap = _daysBetween(point.date, target).abs();
      if (gap < nearestGap) {
        nearest = point;
        nearestGap = gap;
      }
    }
    setState(() => _scrubbed = nearest);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.journalColors;
    final theme = Theme.of(context);
    final tickStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final scrubbed = _scrubbed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: JournalSpacing.x5,
          child: Text(
            scrubbed == null ? '' : _scrubText(scrubbed),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: JournalSpacing.x2),
        SizedBox(
          height: _chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: JournalSpacing.x5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('+1', style: tickStyle),
                    Text('0', style: tickStyle),
                    Text('-1', style: tickStyle),
                  ],
                ),
              ),
              const SizedBox(width: JournalSpacing.x2),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    // A stable key so a test can find this exact gesture
                    // area and tap a known fraction across it, rather than
                    // guessing which `GestureDetector` in the tree is
                    // this one -- `SegmentedButton` above has its own.
                    key: const Key('moodTrendScrubArea'),
                    onTapDown: (details) => _scrubAt(
                      details.localPosition.dx,
                      constraints.maxWidth,
                    ),
                    onPanStart: (details) => _scrubAt(
                      details.localPosition.dx,
                      constraints.maxWidth,
                    ),
                    onPanUpdate: (details) => _scrubAt(
                      details.localPosition.dx,
                      constraints.maxWidth,
                    ),
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, _chartHeight),
                      painter: _MoodTrendPainter(
                        points: widget.points,
                        from: widget.from,
                        totalDays: _totalDays,
                        lineColor: colors.onSurfaceVariant,
                        zeroLineColor: colors.hairline,
                        positiveColor: colors.feelings.uplifted,
                        negativeColor: colors.feelings.low,
                        scrubColor: colors.outline,
                        scrubbedDate: scrubbed?.date,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Draws the zero line, the line segments between date-adjacent scored
/// days, each scored day's point, and the scrub marker.
///
/// A day with a null score is never drawn as a point and never anchors a
/// line segment -- see [MoodSeriesPoint.score]'s doc for why that is a gap
/// rather than a zero. A line segment is drawn between two scored days only
/// when their dates are exactly one day apart; anything else -- a null-score
/// day between them, or days genuinely missing from the response because
/// nothing was logged -- leaves the gap alone rather than bridging it.
class _MoodTrendPainter extends CustomPainter {
  _MoodTrendPainter({
    required this.points,
    required this.from,
    required this.totalDays,
    required this.lineColor,
    required this.zeroLineColor,
    required this.positiveColor,
    required this.negativeColor,
    required this.scrubColor,
    required this.scrubbedDate,
  });

  final List<MoodSeriesPoint> points;
  final CalendarDate from;
  final int totalDays;
  final Color lineColor;
  final Color zeroLineColor;
  final Color positiveColor;
  final Color negativeColor;
  final Color scrubColor;
  final CalendarDate? scrubbedDate;

  double _xFor(CalendarDate date, double width) {
    final span = (totalDays - 1).clamp(1, totalDays);
    return width * _daysBetween(from, date) / span;
  }

  double _yFor(double score, double height) =>
      height * (1 - (score.clamp(-1.0, 1.0) + 1) / 2);

  /// A day's emphasis, in `[0, 1]`, from its entry count: a lone entry sits
  /// at 0, ten or more entries sit at 1. Both the point's radius and its
  /// opacity ride on this, so a thin day is unmistakably a thin day rather
  /// than a confident one drawn small.
  double _emphasis(int entryCount) => (entryCount.clamp(1, 10) - 1) / 9;

  @override
  void paint(Canvas canvas, Size size) {
    final zeroY = _yFor(0, size.height);
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = zeroLineColor
        ..strokeWidth = 1,
    );

    final scored = [
      for (final point in points)
        if (point.score != null) point,
    ];

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < scored.length; i++) {
      final prev = scored[i - 1];
      final curr = scored[i];
      if (_daysBetween(prev.date, curr.date) != 1) continue;
      canvas.drawLine(
        Offset(_xFor(prev.date, size.width), _yFor(prev.score!, size.height)),
        Offset(_xFor(curr.date, size.width), _yFor(curr.score!, size.height)),
        linePaint,
      );
    }

    for (final point in scored) {
      final emphasis = _emphasis(point.entryCount);
      final color = point.score! >= 0 ? positiveColor : negativeColor;
      canvas.drawCircle(
        Offset(_xFor(point.date, size.width), _yFor(point.score!, size.height)),
        2 + 2.5 * emphasis,
        Paint()..color = color.withValues(alpha: 0.35 + 0.65 * emphasis),
      );
    }

    if (scrubbedDate case final date?) {
      final x = _xFor(date, size.width);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = scrubColor.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MoodTrendPainter oldDelegate) =>
      !identical(points, oldDelegate.points) ||
      from != oldDelegate.from ||
      totalDays != oldDelegate.totalDays ||
      lineColor != oldDelegate.lineColor ||
      zeroLineColor != oldDelegate.zeroLineColor ||
      positiveColor != oldDelegate.positiveColor ||
      negativeColor != oldDelegate.negativeColor ||
      scrubColor != oldDelegate.scrubColor ||
      scrubbedDate != oldDelegate.scrubbedDate;
}

/// Whole days between two calendar dates -- [b] minus [a], which is negative
/// when [b] falls before [a].
int _daysBetween(CalendarDate a, CalendarDate b) =>
    b.toDateTime().difference(a.toDateTime()).inDays;

final DateFormat _tooltipDateFormat = DateFormat('MMMM d');

/// The scrub tooltip's text: "August 25, score 0.62, 3 entries", or, for a
/// day that was logged but never confirmed a feeling, "August 25, no
/// confirmed feelings, 3 entries".
String _scrubText(MoodSeriesPoint point) {
  final date = _tooltipDateFormat.format(point.date.toDateTime());
  final middle = switch (point.score) {
    final score? => 'score ${_formatSigned(score, 2)}',
    null => 'no confirmed feelings',
  };
  return '$date, $middle, ${point.entryCount} entries';
}

/// The `Semantics` summary sentence: "Mood over the last 30 days: average
/// −0.1, lowest August 12, highest August 25, based on 41 entries."
///
/// [allPoints] supplies the entry total -- every logged day in range, scored
/// or not -- while [scored] supplies the average and the extremes, since a
/// null-score day has no score to average or compare.
String _buildSummary(
  MoodTrendPeriod period,
  List<MoodSeriesPoint> allPoints,
  List<MoodSeriesPoint> scored,
) {
  final average =
      scored.map((point) => point.score!).reduce((a, b) => a + b) /
      scored.length;

  var lowest = scored.first;
  var highest = scored.first;
  for (final point in scored.skip(1)) {
    if (point.score! < lowest.score!) lowest = point;
    if (point.score! > highest.score!) highest = point;
  }

  final totalEntries = allPoints.fold<int>(
    0,
    (sum, point) => sum + point.entryCount,
  );

  return 'Mood over ${period.summaryLabel}: average ${_formatSigned(average, 1)}, '
      'lowest ${_tooltipDateFormat.format(lowest.date.toDateTime())}, '
      'highest ${_tooltipDateFormat.format(highest.date.toDateTime())}, '
      'based on $totalEntries entries.';
}

/// Formats [value] to [decimals] places, normalising a rounded negative
/// zero (`-0.0`) to the plain positive form so the summary never reads
/// "average -0.0" for a mood that nets out to nothing.
String _formatSigned(double value, int decimals) {
  final rounded = double.parse(value.toStringAsFixed(decimals));
  return (rounded == 0 ? 0.0 : rounded).toStringAsFixed(decimals);
}

/// Maps a sealed [ApiError] to user-facing text, matching
/// `insights_screen.dart`'s own `_messageFor` -- duplicated rather than
/// shared so this chart's edit to that file stays additive.
String _messageFor(ApiError error) => switch (error) {
  BackendNotConfigured() => 'Set your server address in Settings.',
  NetworkFailure() => 'Could not reach the server.',
  Unauthorized() => 'Please sign in again.',
  HttpFailure(:final message) => message,
};
