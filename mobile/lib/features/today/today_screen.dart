import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/entry.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/journal_fab_clearance.dart';
import '../../core/widgets/journal_page_wash.dart';
import '../experiments/active_experiment_banner.dart';
import 'day_summary_card.dart';
import 'entry_card.dart';
import 'today_controller.dart';
import 'writing_streak_line.dart';

/// The app's home screen: one day's entries under a summary of that day.
/// Opens on today.
///
/// The day it reads is not fixed: swiping the page sideways walks a day at
/// a time, which is how a diary is actually re-read, while the calendar
/// stays the way to jump somewhere far away. The stepper in the header does
/// the same thing with a tap — a swipe is faster and the only way some
/// people will find it, but it is invisible, unreachable from a screen
/// reader, and impossible on a page just handed to someone, so it is never
/// the only way in.
class TodayScreen extends ConsumerStatefulWidget {
  /// Builds the Today screen. [onNewEntry] and [onOpenEntry] default to
  /// pushing the composer and entry-detail routes; a caller (or a test)
  /// passes its own to observe the call instead of depending on those
  /// other routes existing.
  const TodayScreen({
    super.key,
    this.onNewEntry,
    this.onOpenEntry,
    this.onOpenExperiment,
  });

  /// Called to start a new entry. Defaults to `context.push('/compose')`.
  final VoidCallback? onNewEntry;

  /// Called to open [Entry] in the entry-detail screen. Defaults to
  /// `context.push('/entry/{id}/{date}')`.
  final ValueChanged<Entry>? onOpenEntry;

  /// Called with the active experiment's id when the experiment banner
  /// (R-3b) is tapped. Defaults to `context.push('/experiments/{id}')`.
  final ValueChanged<String>? onOpenExperiment;

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _pageAnimation = AnimationController(
    vsync: this,
  );

  /// How far the page is currently dragged/animated sideways, in pixels.
  /// Zero is centred; [_pageAnimation] runs 0..1 over
  /// `[-_viewportWidth, _viewportWidth]` so a drag and a settle animation
  /// share one number.
  double _pageOffsetPx = 0;
  double _dragAccumulatorPx = 0;
  double _viewportWidth = 0;
  bool _expandFab = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    // Refresh on first show, matching the "every resume" hook below.
    Future.microtask(
      () => ref.read(todayControllerProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pageAnimation.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(todayControllerProvider.notifier).refresh();
    }
  }

  void _onScroll() {
    final expand =
        _scrollController.position.pixels < 24 ||
        !_scrollController.position.hasContentDimensions;
    if (expand != _expandFab) setState(() => _expandFab = expand);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final controller = ref.read(todayControllerProvider.notifier);
    // Today is the last page there is. Dragging past it still moves, but
    // heavily damped — the resistance says "nothing over here" where a
    // frozen page would read as a dropped gesture.
    final followed = details.delta.dx < 0 && !controller.canGoForward
        ? details.delta.dx * 0.2
        : details.delta.dx;
    _dragAccumulatorPx = (_dragAccumulatorPx + followed).clamp(
      -_viewportWidth,
      _viewportWidth,
    );
    setState(() => _pageOffsetPx = _dragAccumulatorPx);
  }

  Future<void> _onHorizontalDragEnd(DragEndDetails details) async {
    final controller = ref.read(todayControllerProvider.notifier);
    // A fifth of the page: short enough to flick, long enough that a
    // sloppy diagonal scroll does not change the day out from under the
    // reader.
    final commit = _viewportWidth * 0.2;
    final dragged = _dragAccumulatorPx;
    _dragAccumulatorPx = 0;
    if (dragged >= commit) {
      await _turnPage(toPast: true, changeDay: controller.showPreviousDay);
    } else if (dragged <= -commit && controller.canGoForward) {
      await _turnPage(toPast: false, changeDay: controller.showNextDay);
    } else {
      await _settleTo(0);
    }
  }

  /// Carries the current page off the way it was dragged, changes the day
  /// while it is out of sight, and brings the new one in from the far
  /// side. There is no frame in which the old day and the new one are both
  /// visible, and the day swiped towards is the direction it comes from.
  Future<void> _turnPage({
    required bool toPast,
    required Future<void> Function() changeDay,
  }) async {
    final exit = toPast ? _viewportWidth : -_viewportWidth;
    await _settleTo(exit, duration: const Duration(milliseconds: 140));
    await changeDay();
    if (!mounted) return;
    setState(() => _pageOffsetPx = -exit);
    await _settleTo(0);
  }

  Future<void> _settleTo(
    double target, {
    Duration duration = const Duration(milliseconds: 220),
  }) async {
    final start = _pageOffsetPx;
    _pageAnimation
      ..duration = duration
      ..value = 0;
    void listener() {
      setState(
        () => _pageOffsetPx = start + (target - start) * _pageAnimation.value,
      );
    }

    _pageAnimation.addListener(listener);
    await _pageAnimation.forward();
    _pageAnimation.removeListener(listener);
    if (mounted) setState(() => _pageOffsetPx = target);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todayControllerProvider);
    final controller = ref.read(todayControllerProvider.notifier);
    final newEntry = widget.onNewEntry ?? () => context.push('/compose');
    final openEntry =
        widget.onOpenEntry ??
        (entry) => context.push('/entry/${entry.id}/${entry.entryDate}');
    final openExperiment =
        widget.onOpenExperiment ?? (id) => context.push('/experiments/$id');

    ref.listen(todayControllerProvider.select((s) => s.errorMessage), (
      previous,
      next,
    ) {
      if (next == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(next)));
      controller.dismissError();
    });

    final isToday = controller.isToday;
    // An entry is always written *now* — there is no back-dating in the
    // composer — so while reading a past day the button says which day it
    // would write into, and pressing it brings the page back to today.
    final fabLabel = isToday ? 'Write an entry' : 'Write for today';
    // #155: `FloatingActionButton.extended`'s `extendedSizeConstraints`
    // locks its *height* but leaves its width, and its label `Text`,
    // completely unconstrained -- Flutter sizes the pill to whatever the
    // label needs. At 320dp/textScale 2.0 "Write an entry" alone measures
    // well past the screen width, so the button was rendering off both
    // the left and right edges, silently (no `RenderFlex` overflow, so
    // nothing threw). Wrapping the label to a second line is not an
    // option either -- the button's *height* is genuinely fixed, so a
    // two-line label would just overflow vertically instead. The existing
    // scroll-driven collapse-to-"+" already has everywhere this needs: a
    // real measurement decides whether the label fits *before* asking for
    // it, and the icon already carries the accessible name once collapsed.
    final canExtendFab = _extendedFabLabelFits(
      context,
      label: fabLabel,
      viewportWidth: MediaQuery.sizeOf(context).width,
    );
    final showExtendedFab = _expandFab && canExtendFab;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (!isToday) controller.showToday();
          newEntry();
        },
        isExtended: showExtendedFab,
        icon: Icon(
          Icons.add,
          // The label is the accessible name while it is on screen; once
          // the button collapses (by scroll position or because it would
          // not fit) the icon has to carry it.
          semanticLabel: showExtendedFab ? null : fabLabel,
        ),
        label: Text(fabLabel),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: JournalPageWash()),
          LayoutBuilder(
            builder: (context, constraints) {
              _viewportWidth = constraints.maxWidth;
              return GestureDetector(
                onHorizontalDragUpdate: _onHorizontalDragUpdate,
                onHorizontalDragEnd: (details) => _onHorizontalDragEnd(details),
                onHorizontalDragCancel: () => _settleTo(0),
                child: RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: Transform.translate(
                    offset: Offset(_pageOffsetPx, 0),
                    child: ListView(
                      controller: _scrollController,
                      // The wash is painted over the whole screen, status bar
                      // included, and the inset is handed to the list's own
                      // padding instead of to a `SafeArea` — otherwise the
                      // gradient starts below the status bar and the top of the
                      // page reads as a seam. Without adding it back here, the
                      // date sits underneath the clock.
                      padding: EdgeInsets.fromLTRB(
                        JournalSpacing.x4,
                        MediaQuery.paddingOf(context).top + JournalSpacing.x5,
                        JournalSpacing.x4,
                        // [journalFabScrollClearance], not a bare number: the
                        // FAB's collapse-to-"+" on scroll (kept intact here --
                        // see the class doc) never actually shrinks its
                        // height, only its width, so one fixed constant
                        // clears it at every scroll position rather than
                        // needing to track which state the button is in.
                        journalFabScrollClearance,
                      ),
                      children: [
                        _TodayHeader(
                          date: state.date,
                          today: controller.today,
                          canGoForward: controller.canGoForward,
                          onPreviousDay: controller.showPreviousDay,
                          onNextDay: controller.showNextDay,
                          onToday: controller.showToday,
                        ),
                        // The active-experiment banner (R-3b): above the
                        // streak line and the backdate nudge below it,
                        // because it is the one live, time-bound thing on
                        // this header -- a countdown the reader is
                        // mid-way through, not a passive fact like the
                        // streak or an occasional nudge. Today-only, the
                        // same as both.
                        if (state.activeExperiment case final experiment?
                            when isToday) ...[
                          const SizedBox(height: JournalSpacing.x3),
                          ActiveExperimentBanner(
                            experiment: experiment,
                            today: controller.today,
                            onTap: () => openExperiment(experiment.id),
                          ),
                        ],
                        // Only on today, and only once the streak is worth
                        // naming (#40) -- [TodayState.streakDays] is already
                        // zero on a past day, so this stays out of the way
                        // there without a second check.
                        if (isToday &&
                            state.streakDays >=
                                minVisibleWritingStreakDays) ...[
                          const SizedBox(height: JournalSpacing.x2),
                          WritingStreakLine(streakDays: state.streakDays),
                        ],
                        // The first-week backdating nudge (#36): only while
                        // the diary is new enough that filling in a missed
                        // day or two would meaningfully speed up its first
                        // patterns, only on Today (never while paging
                        // through history), and never once dismissed.
                        if (isToday &&
                            !state.nudgeDismissed &&
                            state.hasLoaded &&
                            state.totalEntries <
                                backdateNudgeEntryThreshold) ...[
                          const SizedBox(height: JournalSpacing.x3),
                          _BackdateNudgeCard(
                            onWriteYesterday: () {
                              final yesterday = controller.today.addDays(-1);
                              context.push('/compose?date=$yesterday');
                            },
                            onDismiss: () => unawaited(
                              controller.dismissBackdateNudge(),
                            ),
                          ),
                        ],
                        const SizedBox(height: JournalSpacing.x5),
                        if (!state.hasLoaded)
                          const Padding(
                            padding: EdgeInsets.all(JournalSpacing.x7),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (state.entries.isEmpty)
                          EmptyState(
                            icon: const Icon(Icons.auto_awesome, size: 24),
                            title: Text(
                              isToday
                                  ? 'Nothing yet today'
                                  : 'Nothing was written',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            supporting: Text(
                              isToday
                                  ? 'Whatever just happened is worth a line. '
                                        'A sentence counts.'
                                  : 'This day has no entries. Days you did '
                                        'write are marked on the calendar.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            action: isToday
                                ? PillButton(
                                    onPressed: newEntry,
                                    child: const Text('Write an entry'),
                                  )
                                : null,
                          )
                        else ...[
                          DaySummaryCard(
                            entries: state.entries,
                            summary: state.daySummary,
                            isToday: isToday,
                          ),
                          const SizedBox(height: JournalSpacing.x2),
                          for (final entry in state.entries) ...[
                            const SizedBox(height: JournalSpacing.x3),
                            EntryCard(
                              key: ValueKey(entry.id),
                              entry: entry,
                              onTap: () => openEntry(entry),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The header: an eyebrow and a title that never repeat each other, and the
/// day stepper.
class _TodayHeader extends StatelessWidget {
  const _TodayHeader({
    required this.date,
    required this.today,
    required this.canGoForward,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onToday,
  });

  final CalendarDate date;
  final CalendarDate today;
  final bool canGoForward;
  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) => PageHeader(
    eyebrow: Eyebrow(_eyebrowText(date, today)),
    title: Text(
      _titleText(date, today),
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    // `PageHeader.actions` lays these out in a shrink-wrapped row (no
    // flexible space between them), so the day stepper and "Today" sit
    // side by side rather than with "Today" pushed to the far edge —
    // everything the header needs is still present and reachable, just
    // laid out more plainly than a `weight(1f)`-spaced row would.
    actions: [
      _DayStepButton(
        onPressed: onPreviousDay,
        description: 'Previous day',
        icon: Icons.chevron_left,
      ),
      _DayStepButton(
        onPressed: canGoForward ? onNextDay : null,
        description: 'Next day',
        icon: Icons.chevron_right,
      ),
      // Only offered when it would do something: on today it would be a
      // control that reloads the page, which is the button this screen
      // just got rid of.
      if (date != today)
        SecondaryPillButton(onPressed: onToday, child: const Text('Today')),
    ],
  );
}

/// One step of the day stepper: a 48dp bounded icon button, sized for a
/// thumb rather than the icon.
class _DayStepButton extends StatelessWidget {
  const _DayStepButton({
    required this.onPressed,
    required this.description,
    required this.icon,
  });

  final VoidCallback? onPressed;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: JournalSpacing.x7,
    height: JournalSpacing.x7,
    child: Semantics(
      label: description,
      button: true,
      enabled: onPressed != null,
      child: ExcludeSemantics(
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          ),
          child: Icon(icon),
        ),
      ),
    ),
  );
}

/// The Material 3 geometry `_FABDefaultsM3` (in
/// `package:flutter/src/material/floating_action_button.dart`, not exposed
/// as public constants) gives an *extended* [FloatingActionButton] around
/// its label: the icon, the icon-label gap, and the horizontal content
/// padding either side. [_extendedFabLabelFits] needs these to know how
/// much width is actually left for the label itself.
const double _fabIconSize = 24;
const double _fabIconLabelGap = 8; // extendedIconLabelSpacing
const double _fabExtendedPadding = 16 + 20; // extendedPadding start + end

/// Whether [label] fits on one line inside an extended
/// [FloatingActionButton] at [viewportWidth] without the button growing
/// wider than the screen -- see the call site in [_TodayScreenState.build]
/// for why this has to be measured rather than assumed. Uses the real
/// [TextStyle] Flutter's M3 default gives an extended FAB's label
/// (`textTheme.labelLarge`, see `_FABDefaultsM3.extendedTextStyle`) and the
/// real [TextScaler] from [context], the way `day_summary_card.dart`'s
/// `_measure` and `calendar_screen.dart`'s `_measureHeight` already
/// measure their own screens' real geometry rather than guessing from a
/// character count.
bool _extendedFabLabelFits(
  BuildContext context, {
  required String label,
  required double viewportWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: Theme.of(context).textTheme.labelLarge,
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final available =
      viewportWidth -
      2 * kFloatingActionButtonMargin -
      _fabIconSize -
      _fabIconLabelGap -
      _fabExtendedPadding;
  return painter.width <= available;
}

/// On today and yesterday the title is the word for the day and the
/// eyebrow spells the date out; further back the title *is* the date, so
/// the eyebrow shrinks to the weekday.
String _eyebrowText(CalendarDate date, CalendarDate today) {
  if (date == today || date == today.addDays(-1)) {
    return DateFormat('EEEE, MMMM d').format(date.toDateTime());
  }
  return DateFormat('EEEE').format(date.toDateTime());
}

String _titleText(CalendarDate date, CalendarDate today) {
  if (date == today) return 'Today';
  if (date == today.addDays(-1)) return 'Yesterday';
  if (date.year == today.year) {
    return DateFormat('MMMM d').format(date.toDateTime());
  }
  return DateFormat('MMMM d, yyyy').format(date.toDateTime());
}

/// "How was yesterday?" -- the first-week backdating nudge (#36), offering
/// to open the composer for yesterday. Dismissible on its own, the same
/// shape the composer's own restored-draft notice uses: an `x` that clears
/// the card without doing anything else, so declining costs one tap and
/// nothing more.
class _BackdateNudgeCard extends StatelessWidget {
  const _BackdateNudgeCard({
    required this.onWriteYesterday,
    required this.onDismiss,
  });

  final VoidCallback onWriteYesterday;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'How was yesterday?',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              // `tooltip` alone would only reach the semantics tree's
              // `tooltip` field, not its `label` -- the accessible name a
              // screen reader announces -- so this replaces `IconButton`'s
              // own semantics with an explicit one (the same pattern
              // `pattern_echo_panel.dart`'s dismiss button uses).
              //
              // The touch target is fixed at the 48dp floor
              // (JournalSpacing.x7) via `constraints`' minWidth/minHeight,
              // with `visualDensity: compact` dropped -- it was previously
              // paired with a bare `BoxConstraints()` that set no minimum
              // at all, so this "×" shrank to whatever compact density
              // plus zero padding left around an 18dp icon, well under
              // the platform's own minimum (#150 task 4). Keeping
              // `compact` here would still have undercut the floor: it
              // subtracts a fixed 8dp from both axes of *any* constraints
              // handed to it, `minWidth`/`minHeight` included.
              Semantics(
                container: true,
                button: true,
                label: 'Dismiss',
                onTap: onDismiss,
                child: ExcludeSemantics(
                  child: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Dismiss',
                    onPressed: onDismiss,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: JournalSpacing.x7,
                      minHeight: JournalSpacing.x7,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: JournalSpacing.x1),
          Text(
            'Adding a day or two helps your patterns appear sooner.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: JournalSpacing.x3),
          SecondaryPillButton(
            onPressed: onWriteYesterday,
            child: const Text('Write about yesterday'),
          ),
        ],
      ),
    );
  }
}
