/// @docImport '../../core/widgets/feeling_chips.dart';
library;

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
import '../../core/theme/journal_palette.dart';
import '../../core/theme/journal_typography.dart';
import '../../core/widgets/feeling_accent.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/journal_page_wash.dart';
import 'calendar_controller.dart';
import 'year_grid.dart';

/// The month name and year, e.g. "August 2026".
final DateFormat _monthLabelFormat = DateFormat.yMMMM();

/// Monday-first weekday headers over the grid.
const List<String> _weekdayLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

/// The strongest rating a day cell's intensity bar is drawn against.
///
/// The calendar does not fetch Insights' own served constants for this — one
/// more request just to size a 24-pixel bar is not worth it — so this reads
/// the placeholder's `maxIntensity` instead of a bare `5`, at least naming
/// where the number comes from.
final int _barMaxIntensity = EngineConstants.placeholder.maxIntensity;

/// The entry count a day cell's volume bar reads as "full".
///
/// 5 rather than some larger, "truly maxed out" figure, matching the width
/// steps UX-9b specifies: 1 entry → 20%, 5 or more entries → 100%. #72 made
/// this the real per-day entry count from `GET /monthly-summary`
/// (`days[].entry_count`); before that, [_VolumeBar] read `feelings.length`
/// — the distinct-feeling count — as a stand-in, which this same constant
/// and mapping already fit.
const int _volumeBarMaxCount = 5;

/// Which of the calendar's two views is on screen: the month grid this
/// screen has always shown, or the Year in Pixels grid (CH-2).
///
/// Plain widget state, not a provider: which view is showing is not data
/// either grid's own controller needs to know about, and it resets to
/// [month] every time this screen is rebuilt from scratch — the same as
/// the month grid's own choice of month never surviving a full app
/// restart.
enum _CalendarViewMode { month, year }

/// The month-at-a-glance calendar: a Monday-first grid of every day this
/// month, and a totals panel below it, with a toggle to the Year in Pixels
/// grid (CH-2).
///
/// Reloads on `AppLifecycleState.resumed`, for whichever month is on screen
/// at that moment — not necessarily the one the screen opened on, since the
/// user may have navigated with the month switcher in between. The Year in
/// Pixels grid keeps its own state in `YearGridController` and is not part
/// of that reload — see its own doc for why.
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
  _CalendarViewMode _mode = _CalendarViewMode.month;

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
                SegmentedButton<_CalendarViewMode>(
                  segments: const [
                    ButtonSegment(
                      value: _CalendarViewMode.month,
                      label: Text('Month'),
                    ),
                    ButtonSegment(
                      value: _CalendarViewMode.year,
                      label: Text('Year'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) =>
                      setState(() => _mode = selection.first),
                ),
                const SizedBox(height: JournalSpacing.x3),
                if (_mode == _CalendarViewMode.year)
                  YearGrid(onOpenDay: _openDay)
                else ...[
                  _MonthSwitcher(
                    month: state.month,
                    onPrevious: notifier.previousMonth,
                    onNext: notifier.nextMonth,
                  ),
                  const SizedBox(height: JournalSpacing.x3),
                  if (!state.hasLoaded)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: JournalSpacing.x7,
                      ),
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
/// A day with entries and an empty day differ by fill as well as by their
/// dots and bars, so the distinction survives greyscale and colour
/// blindness: a logged day gets a filled surface with a hairline border and
/// is the loudest thing on the grid; an empty day gets nothing but its own
/// dimmed number on the plain page — no border of any kind, dashed or
/// otherwise (UX-9b). `DashedBorder`
/// (`core/widgets/journal_dashed_border.dart`) stays reserved for a day
/// this grid cannot be entered for at all (a future day, once month
/// navigation grows one — out of scope here); every day in the current
/// grid can be tapped, so none of them draw it. Today gets a ring, not a
/// fill — a fill would compete with "this day has entries", which is what
/// a logged cell's background already means.
///
/// **The volume signal reads the real per-day entry count.** `GET
/// /monthly-summary` (`backend/src/monthly-summary/monthly-summary.service.ts`)
/// carries `days[].entry_count` (#72) alongside `days[].feelings` — the
/// *distinct set* of feeling keys logged that day, a different and smaller
/// number whenever several entries share a feeling. [_VolumeBar] reads
/// `entry_count`, not `feelings.length`, so a day where many entries share
/// one feeling — 15 entries all "grateful" — renders a full bar rather than
/// the single-entry-looking bar `feelings.length` would have drawn.
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
                FeelingDot(color: feeling.accent(journal), size: 6),
                const SizedBox(width: 3),
              ],
            ],
          ),
          const SizedBox(height: 2),
          _VolumeBar(
            key: ValueKey('calendarVolumeBar-$date'),
            count: day?.entryCount ?? 0,
            hairline: journal.hairline,
            fill: theme.colorScheme.primary,
          ),
          if (intensity != null) ...[
            const SizedBox(height: 2),
            _IntensityBar(
              key: ValueKey('calendarIntensityBar-$date'),
              intensity: intensity,
              hairline: journal.hairline,
              fill: theme.colorScheme.primary,
            ),
          ],
        ],
      ],
    );

    // Empty cells draw nothing at all — no fill, no border, dashed or
    // otherwise — so the dimmed number is the only mark on the page. See
    // the class doc for why.
    final inner = logged
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border.all(color: journal.hairline),
              borderRadius: shape,
            ),
            child: Center(child: content),
          )
        : Center(child: content);

    return Semantics(
      key: ValueKey('calendarDayCell-$date'),
      container: true,
      button: true,
      label: _spokenLabel(
        date,
        isToday,
        feelings,
        intensity,
        day?.entryCount ?? 0,
      ),
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

/// `"<day>, today, <N> entries, <feelings>, intensity N"`, or `"<day>, no entries"`.
///
/// "no entries" is said outright, never left implied by the absence of a
/// feelings clause, so a screen reader states plainly what an empty cell
/// looks like to a sighted reader; that branch is keyed on `feelings` being
/// empty (unchanged by #72) rather than on `entryCount`, so it still reads
/// exactly as it did before this field existed, and never says "0 entries".
///
/// States the real entry count (#72), correctly pluralised ("1 entry" vs.
/// "15 entries") — [_VolumeBar] draws the same number as a bar, but a
/// spoken label loses nothing by also saying it outright, and it is what
/// #17 could previously only approximate as a feeling count.
String _spokenLabel(
  CalendarDate date,
  bool isToday,
  List<Feeling> feelings,
  int? intensity,
  int entryCount,
) {
  final buffer = StringBuffer('${date.day}');
  if (isToday) buffer.write(', today');
  if (feelings.isEmpty) {
    buffer.write(', no entries');
  } else {
    final noun = entryCount == 1 ? 'entry' : 'entries';
    buffer.write(', $entryCount $noun');
    buffer.write(', ${feelings.map((f) => f.label).join(', ')}');
    if (intensity != null) buffer.write(', intensity $intensity');
  }
  return buffer.toString();
}

/// The entry-volume signal, as a short bar under the dots.
///
/// [count] is `day.entryCount` at the call site (#72) — the real number of
/// entries logged that day, not `feelings.length`. Mapped in fifths, per
/// UX-9b: 1 entry reads as 20% full, [_volumeBarMaxCount] or more reads as
/// 100%. A logged day still draws a bar at least 20% full even with a
/// single entry — the bar's job is telling a 1-entry day from a 5-entry
/// one, not telling a logged day from an empty one, which the dots above
/// it already do. The 0.2 floor never actually bites: this widget is only
/// built from inside `_DayCell`'s `if (logged)` branch (`logged =
/// feelings.isNotEmpty`), so `count` is always at least 1 whenever this
/// renders at all — kept as a floor rather than removed because it is the
/// honest statement of the mapping's intent, not a workaround.
///
/// **Not a `Stack`.** A `Stack`'s non-positioned children get *loose*
/// constraints by default (`StackFit.loose`): a bare `ColoredBox` — no
/// child of its own — then sizes to the smallest box the constraints
/// allow, which is zero. That is exactly what made this bar and
/// [_IntensityBar] invisible from the day either shipped (#108): the
/// widget tree was correct, `widthFactor` was correct, and the painted
/// bar was a zero-by-zero rectangle. `Stack(fit: StackFit.expand)` would
/// have fixed it too — it forces tight constraints onto every
/// non-positioned child — but that fix works by an incidental side effect
/// of Stack's constraint-propagation mode, not because the track/fill
/// relationship demands a Stack at all. A [DecoratedBox] track holding an
/// [Align]ed, explicitly-sized [FractionallySizedBox] says directly what
/// this is — a track with a proportional fill — and does not depend on
/// which fit mode a future edit might change. `heightFactor: 1` is
/// required despite the track already being 2px tall: [Align] always
/// loosens the constraints it hands to its child (`constraints.loosen()`
/// in `RenderPositionedBox`), so a null `heightFactor` would reintroduce
/// the exact same zero-height trap this comment is warning about.
class _VolumeBar extends StatelessWidget {
  const _VolumeBar({
    super.key,
    required this.count,
    required this.hairline,
    required this.fill,
  });

  final int count;
  final Color hairline;
  final Color fill;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: JournalShapes.full,
    child: SizedBox(
      width: 24,
      height: 2,
      child: DecoratedBox(
        decoration: BoxDecoration(color: hairline),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (count / _volumeBarMaxCount).clamp(0.2, 1),
            heightFactor: 1,
            child: ColoredBox(color: fill),
          ),
        ),
      ),
    ),
  );
}

/// The strongest rating, as a short bar rather than a number.
///
/// The cell already carries a date and a row of dots; a second digit in it
/// reads as a count of entries rather than a rating. A day with no rating
/// shows nothing at all — see the caller — so a diary where nobody uses the
/// intensity dial looks exactly as it did before that feature existed.
///
/// Same track/fill shape as [_VolumeBar], and the same reason it is a
/// [DecoratedBox] + [Align] + [FractionallySizedBox] rather than a `Stack`
/// — see that class's doc for the loose-constraint trap (#108) this
/// avoids.
class _IntensityBar extends StatelessWidget {
  const _IntensityBar({
    super.key,
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
      child: DecoratedBox(
        decoration: BoxDecoration(color: hairline),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (intensity / _barMaxIntensity).clamp(0, 1),
            heightFactor: 1,
            child: ColoredBox(color: fill),
          ),
        ),
      ),
    ),
  );
}

/// This month's average entries per day, a feeling-mix bar (CH-3), and a
/// count for every feeling that was logged at least once.
///
/// [MonthlySummary.totalsByFeeling] arrives already in the backend's own
/// feeling order — built by walking its served vocabulary — so this never
/// re-sorts it, and the bar's segments and the count rows below both walk
/// it in that same order. The dividing rule between the average and the
/// rest appears only when there is something to separate: a month with no
/// entries must not end on a rule with nothing under it, and draws no bar
/// at all (see [_buildFeelingMix]'s empty-month caller below).
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
    // Null exactly when there is nothing logged — an empty month draws no
    // bar and no rows, so nothing downstream ever needs to build a mix for
    // zero feelings.
    final mix = logged.isEmpty ? null : _buildFeelingMix(logged, journal);

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
          if (mix != null) ...[
            const SizedBox(height: JournalSpacing.x4),
            SizedBox(
              width: double.infinity,
              height: 1,
              child: ColoredBox(color: journal.hairline),
            ),
            const SizedBox(height: JournalSpacing.x3),
            _FeelingMixBar(
              key: const ValueKey('feelingMixBar'),
              segments: mix.segments,
              semanticsLabel: _feelingMixSemanticsLabel(logged),
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
                      // The dot matches this row's *segment* colour, not
                      // necessarily the feeling's own valence accent — see
                      // [_buildFeelingMix]. The two are identical unless
                      // this feeling's slice was too thin and got folded
                      // into the trailing "other" segment, in which case
                      // the dot turns that segment's neutral colour so the
                      // list stays truthful about which paint on the bar
                      // this row's count actually contributed to.
                      FeelingDot(
                        color: mix!.swatchByFeelingKey[entry.key.key]!,
                        size: 6,
                      ),
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

/// The fraction, expressed as an exact integer ratio, under which a
/// feeling's slice is too thin to draw on its own and is folded into the
/// trailing "other" segment instead — "~4%" from the issue, as
/// `1 / _mixMergeDenominator` so the comparison in [_buildFeelingMix] stays
/// integer arithmetic (`count * _mixMergeDenominator >= total`) and never
/// drifts on floating-point counts.
const int _mixMergeDenominator = 25;

/// One painted slice of the feeling-mix bar: either one feeling's own
/// share, or the trailing "other" bucket several thin shares were merged
/// into.
class _FeelingMixSegment {
  const _FeelingMixSegment({required this.color, required this.count});

  /// This segment's fill — a feeling's own valence accent, or
  /// [_buildFeelingMix]'s neutral "other" colour.
  final Color color;

  /// This segment's share of the month's total, in entries. [_FeelingMixBar]
  /// uses these as `Expanded` flex values directly, so a segment's rendered
  /// width is exactly proportional to its count without any of the callers
  /// doing floating-point division themselves.
  final int count;
}

/// Splits [logged] into the bar's segments and, in the same pass, a colour
/// for every feeling's row swatch below — so the two can never disagree
/// about which paint a feeling's count landed under.
///
/// Walks [logged] once, in the backend order [MonthlySummary.totalsByFeeling]
/// already arrives in. A feeling whose count clears
/// `1 / _mixMergeDenominator` (~4%) of the month's total keeps its own
/// segment, in that order, painted in its own valence accent
/// ([FeelingAccent.accent] — the same lookup [FeelingChip] resolves its
/// colour through, so the bar and the chips always agree). Everything under
/// that threshold is summed into one "other" segment, painted in
/// [JournalColors.onSurfaceVariant] — a neutral rather than any one
/// feeling's own hue, since "other" may merge feelings of every valence —
/// and **appended last**, regardless of where in backend order its
/// contributors sat. That is the deterministic tie-break this bar needs:
/// two months with the same thin feelings in a different backend order
/// still draw the same bar, because "other" only ever has one possible
/// position. A month where every feeling is under threshold still draws
/// one bar: entirely "other".
({List<_FeelingMixSegment> segments, Map<String, Color> swatchByFeelingKey})
_buildFeelingMix(List<MapEntry<Feeling, int>> logged, JournalColors journal) {
  final total = logged.fold(0, (sum, entry) => sum + entry.value);
  final otherColor = journal.onSurfaceVariant;
  final segments = <_FeelingMixSegment>[];
  final swatchByFeelingKey = <String, Color>{};
  var otherCount = 0;

  for (final entry in logged) {
    final clearsThreshold = entry.value * _mixMergeDenominator >= total;
    if (clearsThreshold) {
      final color = entry.key.accent(journal);
      segments.add(_FeelingMixSegment(color: color, count: entry.value));
      swatchByFeelingKey[entry.key.key] = color;
    } else {
      otherCount += entry.value;
      swatchByFeelingKey[entry.key.key] = otherColor;
    }
  }
  if (otherCount > 0) {
    segments.add(_FeelingMixSegment(color: otherColor, count: otherCount));
  }

  return (segments: segments, swatchByFeelingKey: swatchByFeelingKey);
}

/// `"Feeling mix this month: grateful 3, happy 1, anxious 5"` — every logged
/// feeling in backend order, exactly as [_TotalsPanel]'s own rows list them,
/// regardless of which bar segment (its own, or "other") its count landed
/// in: a screen reader is told the same precise breakdown the sighted count
/// list already shows, not a summary of the bar's own merged segments.
String _feelingMixSemanticsLabel(List<MapEntry<Feeling, int>> logged) {
  final parts = [
    for (final entry in logged) '${entry.key.label} ${entry.value}',
  ];
  return 'Feeling mix this month: ${parts.join(', ')}';
}

/// The stacked bar itself: one [ClipRRect]-rounded row of solid-colour
/// segments, each an `Expanded` sized by [_FeelingMixSegment.count] so
/// widths land exactly proportional to counts with no manual division.
///
/// Decorative: the segments carry no text of their own and are excluded
/// from the semantics tree in favour of the single [semanticsLabel], the
/// same pattern [FeelingDot] uses for the same reason.
class _FeelingMixBar extends StatelessWidget {
  const _FeelingMixBar({
    super.key,
    required this.segments,
    required this.semanticsLabel,
  });

  /// This month's segments, already in the order [_buildFeelingMix] built
  /// them: real feelings first in backend order, "other" last if present.
  final List<_FeelingMixSegment> segments;

  /// The full breakdown a screen reader announces for this bar — see
  /// [_feelingMixSemanticsLabel].
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semanticsLabel,
    child: ExcludeSemantics(
      child: ClipRRect(
        borderRadius: JournalShapes.small,
        child: SizedBox(
          width: double.infinity,
          height: JournalSpacing.x2,
          child: Row(
            children: [
              for (final segment in segments)
                Expanded(
                  flex: segment.count,
                  child: ColoredBox(color: segment.color),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
