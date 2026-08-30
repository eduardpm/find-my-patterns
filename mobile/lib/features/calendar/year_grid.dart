import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/mood_series.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/theme/journal_palette.dart';
import '../../core/widgets/journal.dart';
import 'calendar_controller.dart';
import 'year_grid_controller.dart';

/// The English month names, in order — the single source both
/// [_monthAbbreviation] (the grid's column headers, and the tooltip's short
/// date) and [yearGridSummary] (the accessibility summary's "since June")
/// read from, so the two never drift into naming the same month two
/// different ways. Spelled out rather than read from `DateFormat.MMMM`:
/// every other date this app already shows through `intl` names a day a
/// user wrote, not a fixed English label a locale never changes, so a
/// user's own device locale has no reason to touch this grid's headers.
const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthAbbreviation(int month) => _monthNames[month - 1].substring(0, 3);

/// The single-letter fallback for [_monthAbbreviation] — "J" for January,
/// and for five other months besides, since a year has no shortage of
/// repeated initials. Used only once none of the twelve three-letter
/// abbreviations fits its own column at the real width and scale (see
/// [YearGrid]'s header, and `calendar_screen.dart`'s identically-shaped
/// `_WeekdayHeaderRow`, which the same defect family and the same fix
/// shape already shipped for): every column drops to this together, never
/// only the columns whose glyphs happen to be widest.
String _monthInitial(int month) => _monthNames[month - 1].substring(0, 1);

/// The natural, unwrapped width [text] would render at in [style] under
/// [scaler] — the same `TextPainter`-at-the-real-scaler technique
/// `calendar_screen.dart`'s own `_measureWidth` uses for its weekday
/// header, asking "how wide does this want to be" before deciding whether
/// a column can hold it, rather than guessing from a hardcoded character
/// count.
double _measureWidth(String text, TextStyle? style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();
  return painter.width;
}

/// One cell in the year grid: a real calendar date, and the series point
/// for it if the diary wrote anything that day (`null` when it did not).
class const YearGridCell(
  final CalendarDate date,
  final int monthIndex,
  final int dayIndex,
  final MoodSeriesPoint? point,
);

/// The date at 0-based [monthIndex] (0 = January) and 0-based [dayIndex]
/// (0 = the 1st) in [year], or `null` when that day does not exist — the
/// 31st of a 30-day month, or the 29th/30th of February most years.
CalendarDate? dateAtIndex(int year, int monthIndex, int dayIndex) {
  if (monthIndex < 0 || monthIndex > 11) return null;
  final month = monthIndex + 1;
  final day = dayIndex + 1;
  if (day < 1 || day > YearMonth(year, month).lengthInDays) return null;
  return CalendarDate(year, month, day);
}

/// Every real date in [year] — 12 columns (months), each running only as
/// many rows as that month actually has. A non-existent date such as Feb
/// 30 is never produced here, which is what makes the painter draw nothing
/// for it: it never iterates a cell that was never in this list.
List<YearGridCell> yearGridCells(int year, List<MoodSeriesPoint> points) {
  final byDate = {for (final point in points) point.date: point};
  return [
    for (var month = 0; month < 12; month++)
      for (var day = 0; day < YearMonth(year, month + 1).lengthInDays; day++)
        YearGridCell(
          CalendarDate(year, month + 1, day + 1),
          month,
          day,
          byDate[CalendarDate(year, month + 1, day + 1)],
        ),
  ];
}

/// The grid-level accessibility summary — "2026: 118 days written, mostly
/// positive since June" — read once by [YearGrid] instead of the grid
/// exposing 372 individual semantic nodes (see the class doc for why).
///
/// "Since `<month>`" names the earliest month in an unbroken run of
/// same-signed monthly averages running up to the most recent month with
/// any confirmed score — a diary that turned positive in June and stayed
/// that way reads "since June" the day after, not on some fixed reporting
/// cadence. A year with no scored days at all, or whose most recent scored
/// month averages to exactly zero, omits the clause rather than force a
/// sentiment onto data that does not clearly have one.
String yearGridSummary(int year, List<MoodSeriesPoint> points) {
  final daysWritten = points.length;
  if (daysWritten == 0) return '$year: no days written yet';
  final dayWord = daysWritten == 1 ? 'day' : 'days';
  final base = '$year: $daysWritten $dayWord written';

  final scoresByMonth = <int, List<double>>{};
  for (final point in points) {
    if (point.score case final score?) {
      (scoresByMonth[point.date.month] ??= []).add(score);
    }
  }
  if (scoresByMonth.isEmpty) return base;

  final months = scoresByMonth.keys.toList()..sort();
  double meanOf(int month) {
    final scores = scoresByMonth[month]!;
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  int signOf(double mean) => mean > 0 ? 1 : (mean < 0 ? -1 : 0);

  final latestSign = signOf(meanOf(months.last));
  if (latestSign == 0) return base;

  var sinceMonth = months.last;
  for (var i = months.length - 2; i >= 0; i--) {
    if (signOf(meanOf(months[i])) != latestSign) break;
    sinceMonth = months[i];
  }

  final sentiment = latestSign > 0 ? 'positive' : 'negative';
  return '$base, mostly $sentiment since ${_monthNames[sinceMonth - 1]}';
}

/// The long-press tooltip's text for one cell — the per-cell label the
/// grid never exposes as its own semantic node (see [YearGrid]'s class
/// doc). Deliberately never states a score number: [MoodSeriesPoint.score] is a
/// mean of -1/0/+1 valence scores with no unit a diary-keeper chose, so this
/// names the sentiment it implies instead, the same restraint the wire
/// contract itself applies by shipping a score rather than a word.
String cellTooltipText(
  CalendarDate date,
  MoodSeriesPoint? point, {
  required bool isToday,
}) {
  final label =
      '${_monthAbbreviation(date.month)} ${date.day}, ${date.year}'
      '${isToday ? ' (today)' : ''}';
  if (point == null) return '$label: no entries';

  final entryWord = point.entryCount == 1 ? 'entry' : 'entries';
  final sentiment = switch (point.score) {
    null => 'unconfirmed',
    final score when score > 0 => 'positive',
    final score when score < 0 => 'negative',
    _ => 'neutral',
  };
  return '$label: ${point.entryCount} $entryWord, $sentiment';
}

/// The pixel layout of the year grid: 12 columns (months) x up to 31 rows
/// (the longest possible month), computed from one available width so the
/// painter, the tap/long-press hit test, and this file's own tests all
/// agree on exactly where every cell sits.
class const YearGridGeometry(final double cellSize, final double spacing) {
  /// 12 months across.
  static const int columns = 12;

  /// The longest a month ever runs.
  static const int rows = 31;

  /// Fits [columns] equal square cells and `columns - 1` gaps of a fixed
  /// spacing into [width]. [cellSize] never goes below 1 logical pixel,
  /// so a pathologically narrow layout still produces a paintable (if
  /// illegible) grid instead of an inverted or zero-sized one.
  factory YearGridGeometry.forWidth(double width) {
    const spacing = 2.0;
    final raw = (width - spacing * (columns - 1)) / columns;
    return YearGridGeometry(raw < 1 ? 1 : raw, spacing);
  }

  double get _step => cellSize + spacing;

  /// The grid's total painted size, headers not included.
  Size get size => Size(
    columns * cellSize + (columns - 1) * spacing,
    rows * cellSize + (rows - 1) * spacing,
  );

  /// The rectangle 0-based [monthIndex]/[dayIndex] paints into.
  Rect rectOf(int monthIndex, int dayIndex) =>
      Offset(monthIndex * _step, dayIndex * _step) & Size.square(cellSize);

  /// The (month, day) indices [position] falls inside, or `null` when it
  /// lands outside the grid entirely or in the spacing between cells —
  /// [YearGrid] treats both the same way: no cell to act on.
  (int month, int day)? cellIndexAt(Offset position) {
    final month = (position.dx / _step).floor();
    final day = (position.dy / _step).floor();
    if (month < 0 || month >= columns || day < 0 || day >= rows) return null;
    return rectOf(month, day).contains(position) ? (month, day) : null;
  }
}

/// The Year in Pixels grid: a year of days as a 12x31 grid of colour, one
/// [CustomPaint] pass wide (CH-2).
///
/// A single [GestureDetector] over one painted [CustomPaint] rather than
/// 372 individual cell widgets — the same reason [YearGridGeometry.cellIndexAt]
/// exists: one
/// hit test resolves a tap or a long-press to a cell instead of 372
/// `GestureDetector`s each owning a `RenderObject`. Accessibility follows
/// the same shape: the grid exposes exactly one semantic node, a container
/// carrying [yearGridSummary] as its label, and a per-cell label only
/// appears — as its own live-announcing node — while a long-press holds a
/// cell's tooltip open. That trade only works because nothing about a
/// cell's *state* needs a tap target bigger than itself or a focus ring of
/// its own; a screen-reader user reaches the same information the tooltip
/// shows through the grid's summary and, cell by cell, through the day
/// view a tap opens.
class YearGrid extends ConsumerStatefulWidget {
  /// Creates the year grid.
  ///
  /// [onOpenDay] is a plain callback, not a direct `go_router` dependency —
  /// same as `CalendarScreen` — so this widget and its tests never need a
  /// router in the tree. Defaults to pushing the day-entries route, the
  /// same one `CalendarScreen`'s own month grid pushes.
  const YearGrid({super.key, this.onOpenDay});

  /// Called with the tapped day's date. Defaults to pushing
  /// `/calendar/day/:date`.
  final void Function(CalendarDate date)? onOpenDay;

  @override
  ConsumerState<YearGrid> createState() => _YearGridState();
}

class _YearGridState extends ConsumerState<YearGrid> {
  YearGridCell? _longPressedCell;

  int? _cellsYear;
  List<MoodSeriesPoint>? _cellsSourcePoints;
  List<YearGridCell> _cells = const [];

  /// Recomputes [yearGridCells] only when [year] or [points] actually
  /// changed since the last build — [points] compared by identity, since
  /// [YearGridController] only ever replaces the list wholesale when a
  /// fetch lands, never mutates it in place. Without this, a `setState`
  /// that has nothing to do with the data — showing or hiding the
  /// long-press tooltip — would rebuild a fresh 372-entry list and hand
  /// [CustomPaint] a `cells` value that fails an identity check, forcing a
  /// full repaint of every cell just to show one tooltip.
  List<YearGridCell> _cellsFor(int year, List<MoodSeriesPoint> points) {
    if (_cellsYear != year || !identical(_cellsSourcePoints, points)) {
      _cellsYear = year;
      _cellsSourcePoints = points;
      _cells = yearGridCells(year, points);
    }
    return _cells;
  }

  void _openDay(CalendarDate date) {
    if (widget.onOpenDay case final onOpenDay?) {
      onOpenDay(date);
      return;
    }
    context.push('/calendar/day/$date');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(yearGridControllerProvider, (previous, next) {
      final message = next.errorMessage;
      if (message == null) return;
      _showError(message);
      ref.read(yearGridControllerProvider.notifier).dismissError();
    });

    final state = ref.watch(yearGridControllerProvider);
    final notifier = ref.read(yearGridControllerProvider.notifier);
    final theme = Theme.of(context);
    final journal = context.journalColors;
    final today = CalendarDate.today(now: ref.watch(calendarNowProvider));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _YearSwitcher(
          year: state.year,
          onPrevious: notifier.previousYear,
          onNext: state.year >= today.year ? null : notifier.nextYear,
        ),
        const SizedBox(height: JournalSpacing.x3),
        if (!state.hasLoaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: JournalSpacing.x7),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          JournalCard(
            contentPadding: const EdgeInsets.all(JournalSpacing.x4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final geometry = YearGridGeometry.forWidth(
                  constraints.maxWidth,
                );
                final cells = _cellsFor(state.year, state.points);
                final byIndex = {
                  for (final cell in cells)
                    (cell.monthIndex, cell.dayIndex): cell,
                };

                void handleTapUp(TapUpDetails details) {
                  final index = geometry.cellIndexAt(details.localPosition);
                  final cell = index == null ? null : byIndex[index];
                  if (cell != null) _openDay(cell.date);
                }

                void handleLongPressStart(LongPressStartDetails details) {
                  final index = geometry.cellIndexAt(details.localPosition);
                  setState(
                    () => _longPressedCell = index == null
                        ? null
                        : byIndex[index],
                  );
                }

                void handleLongPressEnd(LongPressEndDetails details) =>
                    setState(() => _longPressedCell = null);

                // Three-letter month abbreviations ("Jan", "Sep", ...) when
                // every column's own share of the header row can hold the
                // widest of them, falling back to single letters for every
                // column at once once it can't -- the sweep measured this
                // row overflowing at *every* matrix cell it checked,
                // including 1.0x, because twelve equal columns across a
                // 320-360dp screen never had room for a three-letter label
                // in the first place, dynamic type or not. Same "measure
                // the widest label once, one shared yes/no decision for
                // every column" shape as `calendar_screen.dart`'s
                // `_WeekdayHeaderRow` (#155), which shipped the identical
                // fix for the identical row-of-near-identical-siblings
                // problem.
                final monthHeaderStyle = theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                );
                final scaler = MediaQuery.textScalerOf(context);
                final columnWidth = geometry.size.width / 12;
                final widestMonthLabelWidth = [
                  for (var month = 1; month <= 12; month++)
                    _measureWidth(
                      _monthAbbreviation(month),
                      monthHeaderStyle,
                      scaler,
                    ),
                ].reduce(math.max);
                final fitsFullAbbreviation =
                    widestMonthLabelWidth <= columnWidth;

                return Semantics(
                  container: true,
                  label: yearGridSummary(state.year, state.points),
                  child: Stack(
                    children: [
                      ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: geometry.size.width,
                              child: Row(
                                children: [
                                  for (var month = 1; month <= 12; month++)
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          fitsFullAbbreviation
                                              ? _monthAbbreviation(month)
                                              : _monthInitial(month),
                                          style: monthHeaderStyle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: JournalSpacing.x1),
                            GestureDetector(
                              key: const Key('yearGridPaintArea'),
                              onTapUp: handleTapUp,
                              onLongPressStart: handleLongPressStart,
                              onLongPressEnd: handleLongPressEnd,
                              child: CustomPaint(
                                size: geometry.size,
                                painter: _YearGridPainter(
                                  cells: cells,
                                  geometry: geometry,
                                  today: today,
                                  journal: journal,
                                  primary: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_longPressedCell case final cell?)
                        _CellTooltip(
                          // The header row sits above the grid, so the
                          // tooltip's own vertical offset has to account for
                          // it too — see the header `SizedBox` height above.
                          gridTop:
                              (theme.textTheme.labelSmall?.fontSize ?? 12) *
                                  1.4 +
                              JournalSpacing.x1,
                          rect: geometry.rectOf(
                            cell.monthIndex,
                            cell.dayIndex,
                          ),
                          gridWidth: geometry.size.width,
                          text: cellTooltipText(
                            cell.date,
                            cell.point,
                            isToday: cell.date == today,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// The ‹ YYYY › header: mirrors `_MonthSwitcher` in
/// `calendar_screen.dart` down to its semantics pattern, but for a year
/// instead of a month, and with [onNext] nullable rather than always
/// wired — `null` is how [YearGrid] disables the forward chevron once the
/// switcher would move past the current year.
class _YearSwitcher extends StatelessWidget {
  const _YearSwitcher({
    required this.year,
    required this.onPrevious,
    required this.onNext,
  });

  final int year;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Semantics(
          container: true,
          button: true,
          label: 'Previous year',
          onTap: onPrevious,
          child: ExcludeSemantics(
            child: IconButton(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous year',
            ),
          ),
        ),
        Text('$year', style: theme.textTheme.titleLarge),
        Semantics(
          container: true,
          button: onNext != null,
          label: 'Next year',
          onTap: onNext,
          child: ExcludeSemantics(
            child: IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next year',
            ),
          ),
        ),
      ],
    );
  }
}

/// The floating bubble a long press opens over one cell — the per-cell
/// label [YearGrid]'s class doc calls out, kept to one live widget instead
/// of one per cell.
class _CellTooltip extends StatelessWidget {
  const _CellTooltip({
    required this.rect,
    required this.text,
    required this.gridWidth,
    required this.gridTop,
  });

  /// The tapped cell's own rectangle, in the grid's local coordinate space
  /// (below the header row).
  final Rect rect;

  final String text;
  final double gridWidth;

  /// The header row's height, so this tooltip's vertical offset lines up
  /// with [rect] even though [rect] itself is header-relative.
  final double gridTop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const bubbleWidth = 168.0;
    const bubbleHeight = 32.0;
    final top = gridTop + rect.top;
    final showAbove = top > bubbleHeight + 4;
    final maxLeft = gridWidth - bubbleWidth;
    return Positioned(
      top: showAbove ? top - bubbleHeight - 4 : top + rect.height + 4,
      left: rect.left.clamp(0, maxLeft < 0 ? 0 : maxLeft),
      width: bubbleWidth,
      child: Semantics(
        liveRegion: true,
        label: text,
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.inverseSurface,
              borderRadius: JournalShapes.small,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: JournalSpacing.x2,
                vertical: JournalSpacing.x1,
              ),
              child: Text(
                text,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onInverseSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints every cell in [cells] in one pass.
///
/// Four states per cell, matching the Task's own list: a scored day fills
/// with [ValenceRamp.colorForScore]'s ramp; a day with entries but no
/// confirmed score fills [JournalColors.surfaceVariant] under a
/// [JournalColors.outline] stroke; a day with no entries at all draws only
/// a near-invisible dot; and a day this list never produced — a
/// non-existent date — is never iterated, so it draws nothing. [today]
/// additionally draws a ring on top of whichever of those a cell already
/// is.
class _YearGridPainter extends CustomPainter {
  _YearGridPainter({
    required this.cells,
    required this.geometry,
    required this.today,
    required this.journal,
    required this.primary,
  });

  final List<YearGridCell> cells;
  final YearGridGeometry geometry;
  final CalendarDate today;
  final JournalColors journal;
  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(geometry.cellSize / 3);
    final fill = Paint()..style = PaintingStyle.fill;
    final outlineStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = journal.outline;
    final ringStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = primary;
    final dotFill = Paint()
      ..style = PaintingStyle.fill
      ..color = journal.hairline.withValues(alpha: 0.6);

    for (final cell in cells) {
      final rect = geometry.rectOf(cell.monthIndex, cell.dayIndex);
      final point = cell.point;
      final score = point?.score;
      if (score != null) {
        fill.color = journal.feelings.colorForScore(score);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), fill);
      } else if (point != null) {
        fill.color = journal.surfaceVariant;
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), fill);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(0.5), radius),
          outlineStroke,
        );
      } else {
        canvas.drawCircle(rect.center, geometry.cellSize * 0.12, dotFill);
      }
      if (cell.date == today) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(0.75), radius),
          ringStroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _YearGridPainter oldDelegate) =>
      oldDelegate.cells != cells ||
      oldDelegate.geometry.cellSize != geometry.cellSize ||
      oldDelegate.geometry.spacing != geometry.spacing ||
      oldDelegate.today != today ||
      oldDelegate.journal != journal ||
      oldDelegate.primary != primary;
}
