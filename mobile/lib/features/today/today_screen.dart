import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/entry.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/journal_page_wash.dart';
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
  const TodayScreen({super.key, this.onNewEntry, this.onOpenEntry});

  /// Called to start a new entry. Defaults to `context.push('/compose')`.
  final VoidCallback? onNewEntry;

  /// Called to open [Entry] in the entry-detail screen. Defaults to
  /// `context.push('/entry/{id}/{date}')`.
  final ValueChanged<Entry>? onOpenEntry;

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

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (!isToday) controller.showToday();
          newEntry();
        },
        isExtended: _expandFab,
        icon: Icon(
          Icons.add,
          // The label is the accessible name while it is on screen; once
          // the button collapses the icon has to carry it.
          semanticLabel: _expandFab ? null : fabLabel,
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
                        // Deep enough that the last entry clears the floating
                        // button rather than ending underneath it.
                        96,
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
