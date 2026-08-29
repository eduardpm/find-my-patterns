import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/feeling.dart';
import '../../core/diary/monthly_summary.dart';
import '../../core/diary/pattern.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/theme/journal_typography.dart';
import '../../core/widgets/feeling_accent.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/journal_dashed_border.dart';
import '../../core/widgets/journal_page_wash.dart';
import 'calendar_controller.dart';

/// The month name and year, e.g. "August 2026".
final DateFormat _monthLabelFormat = DateFormat.yMMMM();

/// Monday-first weekday headers over the grid.
const List<String> _weekdayLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

/// The strongest rating a day cell's bar is drawn against.
///
/// The calendar does not fetch Insights' own served constants for this — one
/// more request just to size a 24-pixel bar is not worth it — so this reads
/// the placeholder's `maxIntensity` instead of a bare `5`, at least naming
/// where the number comes from.
final int _barMaxIntensity = EngineConstants.placeholder.maxIntensity;

/// The month-at-a-glance calendar: a Monday-first grid of every day this
/// month, and a totals panel below it.
///
/// Reloads on `AppLifecycleState.resumed`, for whichever month is on screen
/// at that moment — not necessarily the one the screen opened on, since the
/// user may have navigated with the month switcher in between.
class CalendarScreen extends ConsumerStatefulWidget {
  /// Creates the calendar screen.
  ///
  /// [onOpenDay] is a plain callback rather than a direct `go_router`
  /// dependency, so this screen — and its tests — never need a router in
  /// the tree. Defaults to pushing the day-entries route.
  const CalendarScreen({super.key, this.onOpenDay});

  /// Called with the tapped day's date. Defaults to pushing
  /// `/calendar/day/:date`.
  final void Function(CalendarDate date)? onOpenDay;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(calendarControllerProvider.notifier).reloadCurrentMonth(),
      );
    }
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
    ref.listen(calendarControllerProvider, (previous, next) {
      final message = next.errorMessage;
      if (message == null) return;
      _showError(message);
      ref.read(calendarControllerProvider.notifier).dismissError();
    });

    final state = ref.watch(calendarControllerProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(calendarControllerProvider.notifier);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          const Positioned.fill(child: JournalPageWash()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                JournalSpacing.x4,
                JournalSpacing.x5,
                JournalSpacing.x4,
                JournalSpacing.x7,
              ),
              children: [
                PageHeader(
                  eyebrow: const Eyebrow('Month at a glance'),
                  title: Text('Calendar', style: theme.textTheme.headlineSmall),
                ),
                const SizedBox(height: JournalSpacing.x4),
                _MonthSwitcher(
                  month: state.month,
                  onPrevious: notifier.previousMonth,
                  onNext: notifier.nextMonth,
                ),
                const SizedBox(height: JournalSpacing.x3),
                if (!state.hasLoaded)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: JournalSpacing.x7),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (state.summary case final summary?) ...[
                  JournalCard(
                    contentPadding: const EdgeInsets.all(JournalSpacing.x4),
                    child: _CalendarGrid(
                      month: state.month,
                      days: summary.days,
                      today: CalendarDate.today(
                        now: ref.watch(calendarNowProvider),
                      ),
                      onOpenDay: _openDay,
                    ),
                  ),
                  const SizedBox(height: JournalSpacing.x4),
                  _TotalsPanel(summary),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final YearMonth month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // `tooltip` alone would only reach the semantics tree's `tooltip`
        // field, not its `label` -- the accessible name a screen reader
        // announces -- so this supplies an explicit one, the same pattern
        // `PatternEchoPanel`'s dismiss button uses for the same mismatch.
        Semantics(
          container: true,
          button: true,
          label: 'Previous month',
          onTap: onPrevious,
          child: ExcludeSemantics(
            child: IconButton(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous month',
            ),
          ),
        ),
        Text(
          _monthLabelFormat.format(month.firstDay.toDateTime()),
          style: theme.textTheme.titleLarge,
        ),
        Semantics(
          container: true,
          button: true,
          label: 'Next month',
          onTap: onNext,
          child: ExcludeSemantics(
            child: IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next month',
            ),
          ),
        ),
      ],
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.month,
    required this.days,
    required this.today,
    required this.onOpenDay,
  });

  final YearMonth month;
  final List<DaySummary> days;

  /// Which date counts as "today" for the ring — injectable (see
  /// [calendarNowProvider]) so a test never depends on the real clock.
  final CalendarDate today;
  final void Function(CalendarDate date) onOpenDay;

  @override
  Widget build(BuildContext context) {
    final byDate = {for (final day in days) day.date: day};
    final daysInMonth = month.lengthInDays;
    // Monday-first grid: how many blank cells lead up to day 1.
    final leadingBlanks = (month.firstDay.weekday - DateTime.monday + 7) % 7;

    return Column(
      children: [
        Row(
          children: [
            for (final label in _weekdayLabels)
              Expanded(
                child: Center(child: Eyebrow(label)),
              ),
          ],
        ),
        const SizedBox(height: JournalSpacing.x2),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
            for (var i = 0; i < daysInMonth; i++)
              _DayCell(
                date: month.firstDay.addDays(i),
                day: byDate[month.firstDay.addDays(i)],
                isToday: month.firstDay.addDays(i) == today,
                onTap: onOpenDay,
              ),
          ],
        ),
      ],
    );
  }
}

/// One day in the grid.
///
/// A day with entries and an empty day differ by border style and fill as
/// well as by their dots, so the distinction survives greyscale and colour
/// blindness: logged days get a filled surface with a hairline border,
/// empty days get [DashedBorder]. Today gets a ring, not a fill — a fill
/// would compete with "this day has entries", which is what a logged cell's
/// background already means.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.day,
    required this.isToday,
    required this.onTap,
  });

  final CalendarDate date;
  final DaySummary? day;
  final bool isToday;
  final void Function(CalendarDate date) onTap;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    final theme = Theme.of(context);
    final feelings = day?.feelings ?? const <Feeling>[];
    final logged = feelings.isNotEmpty;
    final intensity = day?.intensity;
    final shape = JournalShapes.medium;

    final numberColor = isToday
        ? theme.colorScheme.primary
        : logged
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${date.day}',
          style: JournalType.tabularFigures(
            theme.textTheme.bodyMedium!,
          ).copyWith(color: numberColor),
        ),
        if (logged) ...[
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final feeling in feelings.take(3)) ...[
                _FeelingDot(color: feeling.accent(journal)),
                const SizedBox(width: 3),
              ],
            ],
          ),
          if (intensity != null) ...[
            const SizedBox(height: 2),
            _IntensityBar(
              intensity: intensity,
              hairline: journal.hairline,
              fill: theme.colorScheme.primary,
            ),
          ],
        ],
      ],
    );

    final inner = DecoratedBox(
      decoration: logged
          ? BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border.all(color: journal.hairline),
              borderRadius: shape,
            )
          : const BoxDecoration(),
      child: logged
          ? Center(child: content)
          : DashedBorder(
              color: journal.hairline,
              borderRadius: shape,
              child: Center(child: content),
            ),
    );

    return Semantics(
      container: true,
      button: true,
      label: _spokenLabel(date, isToday, feelings, intensity),
      onTap: () => onTap(date),
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onTap(date),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: AspectRatio(
                aspectRatio: 1,
                child: isToday
                    ? Container(
                        foregroundDecoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                          borderRadius: shape,
                        ),
                        child: inner,
                      )
                    : inner,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `"<day>, today, <feelings>, intensity N"`, or `"<day>, no entries"`.
///
/// "no entries" is said outright, never left implied by the absence of a
/// feelings clause, so a screen reader states plainly what an empty cell
/// looks like to a sighted reader.
String _spokenLabel(
  CalendarDate date,
  bool isToday,
  List<Feeling> feelings,
  int? intensity,
) {
  final buffer = StringBuffer('${date.day}');
  if (isToday) buffer.write(', today');
  if (feelings.isEmpty) {
    buffer.write(', no entries');
  } else {
    buffer.write(', ${feelings.map((f) => f.label).join(', ')}');
    if (intensity != null) buffer.write(', intensity $intensity');
  }
  return buffer.toString();
}

class _FeelingDot extends StatelessWidget {
  const _FeelingDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

/// The strongest rating, as a short bar rather than a number.
///
/// The cell already carries a date and a row of dots; a second digit in it
/// reads as a count of entries rather than a rating. A day with no rating
/// shows nothing at all — see the caller — so a diary where nobody uses the
/// intensity dial looks exactly as it did before that feature existed.
class _IntensityBar extends StatelessWidget {
  const _IntensityBar({
    required this.intensity,
    required this.hairline,
    required this.fill,
  });

  final int intensity;
  final Color hairline;
  final Color fill;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: JournalShapes.full,
    child: SizedBox(
      width: 24,
      height: 2,
      child: Stack(
        children: [
          ColoredBox(color: hairline),
          FractionallySizedBox(
            widthFactor: (intensity / _barMaxIntensity).clamp(0, 1),
            child: ColoredBox(color: fill),
          ),
        ],
      ),
    ),
  );
}

/// This month's average entries per day, and a count for every feeling that
/// was logged at least once.
///
/// [MonthlySummary.totalsByFeeling] arrives already in the backend's own
/// feeling order — built by walking its served vocabulary — so this never
/// re-sorts it. The dividing rule between the average and the per-feeling
/// rows appears only when there is something to separate: a month with no
/// entries must not end on a rule with nothing under it.
class _TotalsPanel extends StatelessWidget {
  const _TotalsPanel(this.summary);

  final MonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    final theme = Theme.of(context);
    final logged = [
      for (final entry in summary.totalsByFeeling.entries)
        if (entry.value > 0) entry,
    ];

    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('This month'),
          const SizedBox(height: JournalSpacing.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                summary.averageEntriesPerDay.toStringAsFixed(1),
                style: JournalType.tabularFigures(theme.textTheme.displaySmall!)
                    .copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(width: JournalSpacing.x2),
              Text(
                'entries a day',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (logged.isNotEmpty) ...[
            const SizedBox(height: JournalSpacing.x4),
            SizedBox(
              width: double.infinity,
              height: 1,
              child: ColoredBox(color: journal.hairline),
            ),
            const SizedBox(height: JournalSpacing.x3),
          ],
          for (final entry in logged)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: JournalSpacing.x1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _FeelingDot(color: entry.key.accent(journal)),
                      const SizedBox(width: JournalSpacing.x3),
                      Text(entry.key.label, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                  Text(
                    '${entry.value}',
                    style: JournalType.tabularFigures(
                      theme.textTheme.labelLarge!,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
