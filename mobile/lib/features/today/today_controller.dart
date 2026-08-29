import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/diary_providers.dart';
import '../../core/diary/entry.dart';
import '../../core/diary/experiment.dart';
import '../../core/diary/monthly_summary.dart';
import '../../core/diary/writing_streak.dart';
import '../../core/network/api_error.dart';
import 'backdate_nudge_store.dart';

/// How few total entries a diary may have before the first-week backdating
/// nudge ("How was yesterday?" -- #36) is worth showing. Read from the same
/// windowed entry count [TodayController._loadStreak] already fetches for
/// the writing streak (#40) -- see [TodayState.totalEntries]'s doc comment
/// for why that count, rather than a literal all-time total, is what this
/// is compared against.
const int backdateNudgeEntryThreshold = 7;

/// Reads and writes whether the backdating nudge has been dismissed.
///
/// Overridable so tests can substitute an in-memory fake, the same way
/// `composerDraftStoreProvider` works.
final backdateNudgeStoreProvider = Provider<BackdateNudgeStore>(
  (ref) => const SharedPreferencesBackdateNudgeStore(),
);

/// One day's reading state for the Today screen.
class const TodayState(
  final CalendarDate date, {
  final List<Entry> entries = const [],

  /// The backend's own roll-up of [date] — its feelings and its strongest
  /// rating. Read from `GET /monthly-summary` rather than counted here on
  /// purpose: the summary card reports the same numbers the calendar does,
  /// instead of a second opinion computed from whatever entries this
  /// screen happens to have loaded. Null when that call has not landed, or
  /// had nothing for the day.
  final DaySummary? daySummary,

  /// The current writing streak (#40): consecutive days, ending today or
  /// yesterday, with at least one entry -- see [computeWritingStreak] for
  /// the exact rule. Zero both while [date] is not today (the streak line
  /// only ever shows on Today, never while paging through history) and
  /// while nothing has loaded yet, which happens to read the same as "no
  /// streak" and keeps the line hidden either way.
  final int streakDays = 0,

  /// How many entries the diary has written in the last
  /// [writingStreakQueryWindowDays] days (#36) -- summed from the same
  /// `GET /insights/series` call [streakDays] is computed from, so the
  /// nudge-visibility check costs no extra request.
  ///
  /// Not a literal all-time count: for the brand-new diaries the nudge
  /// exists for, every entry ever written is well inside this window, so
  /// the two agree in exactly the case that matters. A diary old enough for
  /// the difference to show already has 7 or more entries either way, which
  /// is the only threshold this is ever compared against
  /// ([backdateNudgeEntryThreshold]). Zero both while [date] is not today
  /// (the same rule [streakDays] follows) and while nothing has loaded yet.
  final int totalEntries = 0,

  /// Whether the backdating nudge card has been dismissed on this device
  /// (#36). Loaded once, in [TodayController.build] -- true is also the
  /// safe default before that load lands, so the card never flashes on
  /// screen for a moment before the dismissal it should already be honouring
  /// is read back.
  final bool nudgeDismissed = true,

  /// The experiment currently running (R-3b), or `null` when none is.
  /// Fetched alongside the writing streak -- see [streakDays]'s doc
  /// comment for why that fetch, and this one, only happen while [date] is
  /// today: an experiment is a fact about the app, not about whichever day
  /// is on screen, and the banner it feeds only ever shows on Today.
  final Experiment? activeExperiment,

  /// A reload is in flight over content that is already on screen.
  final bool isRefreshing = false,

  /// Whether a load has ever finished for [date], successfully or not.
  ///
  /// The full-screen spinner is gated on this rather than on
  /// `entries.isEmpty` — every resume re-runs [TodayController.refresh],
  /// and an empty-list check is still true while that request is in
  /// flight, which flashed the spinner for a full round trip on every tab
  /// switch. After the first load the list simply stays on screen while it
  /// refreshes.
  final bool hasLoaded = false,
  final String? errorMessage,
}) {
  /// A sentinel distinguishing "leave the field alone" from "clear it" for
  /// the two nullable fields [copyWith] can reset — a plain `x ?? this.x`
  /// can never null a field back out once set.
  static const Object _unset = Object();

  /// A copy of this state with the given fields replaced.
  ///
  /// Pass `daySummary: null` or `errorMessage: null` to explicitly clear
  /// either; omit them to leave the current value alone.
  TodayState copyWith({
    List<Entry>? entries,
    Object? daySummary = _unset,
    int? streakDays,
    int? totalEntries,
    bool? nudgeDismissed,
    Object? activeExperiment = _unset,
    bool? isRefreshing,
    bool? hasLoaded,
    Object? errorMessage = _unset,
  }) => TodayState(
    date,
    entries: entries ?? this.entries,
    daySummary: identical(daySummary, _unset)
        ? this.daySummary
        : daySummary as DaySummary?,
    streakDays: streakDays ?? this.streakDays,
    totalEntries: totalEntries ?? this.totalEntries,
    nudgeDismissed: nudgeDismissed ?? this.nudgeDismissed,
    activeExperiment: identical(activeExperiment, _unset)
        ? this.activeExperiment
        : activeExperiment as Experiment?,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
  );
}

/// How long the poll waits between checks, and how long it keeps trying —
/// see [TodayController._watchAnalysis].
const Duration _analysisPollInterval = Duration(seconds: 3);
const Duration _analysisPollTimeout = Duration(seconds: 90);

/// Drives the Today screen: which day is showing, its entries, the
/// backend's day summary, and the analysis poll that keeps a just-written
/// entry's feelings up to date.
///
/// The constructor's `now` and `delay` are the two clock seams a test
/// needs: `now` pins what "today" means (for the forward-step ceiling and
/// the midnight check), and `delay` replaces the real wait in
/// [_watchAnalysis]'s poll loop. Both default to the real clock, and a test
/// overrides the provider with its own construction supplying fakes
/// instead.
class TodayController extends Notifier<TodayState> {
  /// Creates a controller reading the clock through [now] and waiting
  /// through [delay] — both real by default.
  TodayController({this.now = DateTime.now, this.delay = Future.delayed});

  /// Resolves the current instant. The real clock by default; a test pins
  /// this to a fixed time so "today" never depends on when the suite runs.
  final DateTime Function() now;

  /// Awaits between analysis-poll checks. The real delay by default; a
  /// test replaces this with a no-op so [_watchAnalysis]'s loop never
  /// waits on a real clock.
  final Future<void> Function(Duration) delay;

  /// Whether the screen is following "today" rather than sitting on a day
  /// the reader chose.
  ///
  /// It matters at midnight: an app left open overnight on Today should
  /// come back showing the new day, but one parked on last Tuesday must
  /// stay on last Tuesday.
  bool _followsToday = true;

  /// Bumped on every [refresh] and [showDay]; a background load or poll
  /// checks this before writing [state] so a superseded request never
  /// clobbers a later one's result.
  int _generation = 0;

  Future<void>? _analysisWatch;

  /// Resolves once the in-flight analysis poll, if any, has settled.
  ///
  /// A test seam only: production code never awaits this, since the whole
  /// point of firing the poll from [refresh] rather than blocking on it is
  /// that the screen is usable immediately. A test awaits it instead of
  /// pumping the event queue and hoping enough ticks have passed for the
  /// poll's own chain of requests to settle.
  Future<void> get analysisSettled => _analysisWatch ?? Future<void>.value();

  /// Today's date, on the injected clock.
  CalendarDate get today => CalendarDate.today(now: now());

  /// There is no tomorrow to read, so the forward step stops at today.
  bool get canGoForward => state.date < today;

  /// Whether the day currently showing is today.
  bool get isToday => state.date == today;

  @override
  TodayState build() {
    // A write elsewhere -- the composer finishing a new entry, or
    // entry-detail saving an edit or a delete -- may have changed this
    // day's entries or its summary. Refreshing here picks that up even
    // while this screen sits off-screen in the shell's other tabs, so it is
    // already current by the time the reader swipes back to it.
    ref.listen(diaryWriteSignalProvider, (_, _) => refresh());
    Future.microtask(_loadNudgeDismissed);
    return TodayState(today);
  }

  /// Reads whether the backdating nudge was already dismissed on this
  /// device (#36), once per controller lifetime.
  Future<void> _loadNudgeDismissed() async {
    final dismissed = await ref.read(backdateNudgeStoreProvider).isDismissed();
    if (!ref.mounted) return;
    state = state.copyWith(nudgeDismissed: dismissed);
  }

  /// Dismisses the backdating nudge for good on this device (#36).
  Future<void> dismissBackdateNudge() async {
    state = state.copyWith(nudgeDismissed: true);
    await ref.read(backdateNudgeStoreProvider).dismiss();
  }

  /// Shows [date], clamped so it never runs ahead of today.
  ///
  /// Returns the resulting [refresh]'s future -- production callers (the
  /// screen's tap handlers) fire this without awaiting it, same as before;
  /// a test can await it instead of guessing how many ticks a reload
  /// needs.
  Future<void> showDay(CalendarDate date) {
    final target = date > today ? today : date;
    _followsToday = target == today;
    if (target != state.date) {
      // The previous day's entries are cleared rather than left up while
      // the new day loads: a list of entries under the wrong date is
      // worse than a spinner.
      state = TodayState(target);
    }
    return refresh();
  }

  /// Shows the day before the one currently showing.
  Future<void> showPreviousDay() => showDay(state.date.addDays(-1));

  /// Shows the day after the one currently showing, clamped at today.
  Future<void> showNextDay() => showDay(state.date.addDays(1));

  /// Returns to today.
  Future<void> showToday() => showDay(today);

  /// Reloads the day being shown.
  ///
  /// Nothing in the UI has to ask for this beyond the screen's own
  /// lifecycle hooks (first show, every resume, a day change) — pull to
  /// refresh is the one manual escape hatch left, existing for when all of
  /// that still is not enough.
  Future<void> refresh() async {
    // Midnight can pass while the screen sits in the background.
    if (_followsToday && state.date != today) {
      return showDay(today);
    }
    final generation = ++_generation;
    final date = state.date;
    state = state.copyWith(isRefreshing: true, errorMessage: null);
    await _load(date, generation);
    if (generation != _generation) return;
    state = state.copyWith(isRefreshing: false, hasLoaded: true);
    _analysisWatch = _watchAnalysis(date, generation);
  }

  Future<void> _load(CalendarDate date, int generation) async {
    try {
      final entries = await ref.read(entriesApiProvider).listByDate(date);
      if (generation != _generation) return;
      state = state.copyWith(entries: entries);
    } on ApiError catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(errorMessage: error.message);
    }

    // A missing summary is not worth a message of its own: it only
    // enriches the card at the top of the page, the entries themselves
    // carry the day, and a second error snack bar for the same
    // unreachable backend would say nothing new.
    try {
      final monthly = await ref
          .read(monthlySummaryApiProvider)
          .forMonth(YearMonth.fromDate(date));
      if (generation != _generation) return;
      DaySummary? dayForDate;
      for (final day in monthly.days) {
        if (day.date == date) {
          dayForDate = day;
          break;
        }
      }
      state = state.copyWith(daySummary: dayForDate);
    } on ApiError {
      if (generation != _generation) return;
      state = state.copyWith(daySummary: null);
    }

    await _loadStreak(date, generation);
    await _loadActiveExperiment(date, generation);
  }

  /// Refreshes [TodayState.activeExperiment] (R-3b).
  ///
  /// Gated on `date == today` for the same reason [_loadStreak] is: an
  /// active experiment is a fact about the app, not about whichever day is
  /// on screen, so browsing history costs no extra request for a banner
  /// that never shows there. A failed fetch is silent, matching every
  /// other best-effort load in this method -- the banner simply does not
  /// appear until the next successful refresh.
  Future<void> _loadActiveExperiment(CalendarDate date, int generation) async {
    if (date != today) {
      state = state.copyWith(activeExperiment: null);
      return;
    }
    try {
      final experiment = await ref.read(experimentsApiProvider).active();
      if (generation != _generation) return;
      state = state.copyWith(activeExperiment: experiment);
    } on ApiError {
      if (generation != _generation) return;
      state = state.copyWith(activeExperiment: null);
    }
  }

  /// Refreshes [TodayState.streakDays] (#40) and [TodayState.totalEntries]
  /// (#36) from one shared call.
  ///
  /// Only fetched while [date] is today: both are facts about today, not
  /// about whichever day the reader happens to be paging through, so
  /// browsing history neither shows a stale number nor spends a request
  /// re-deriving one nobody will see. A failed fetch is silent, the same
  /// call the [TodayState.daySummary] fetch above makes -- one more quiet
  /// number, not a second error snack bar for a backend already reported
  /// unreachable.
  Future<void> _loadStreak(CalendarDate date, int generation) async {
    if (date != today) {
      state = state.copyWith(streakDays: 0);
      return;
    }
    try {
      final series = await ref
          .read(insightsApiProvider)
          .series(
            from: today.addDays(-(writingStreakQueryWindowDays - 1)),
            to: today,
          );
      if (generation != _generation) return;
      state = state.copyWith(
        streakDays: computeWritingStreak(
          // A day only appears in `points` when it has at least one entry,
          // which is exactly the set the streak counts over.
          entryDates: {for (final point in series.points) point.date},
          today: today,
        ),
        totalEntries: [
          for (final point in series.points) point.entryCount,
        ].fold<int>(0, (sum, count) => sum + count),
      );
    } on ApiError {
      if (generation != _generation) return;
      state = state.copyWith(streakDays: 0, totalEntries: 0);
    }
  }

  /// Keeps reloading while the backend is still analysing an entry on
  /// [date].
  ///
  /// Analysis runs in a worker after an entry is saved, so the feelings on
  /// a just-written entry land a few seconds after it appears — precisely
  /// the moment someone would reach for a refresh button, so the screen
  /// waits for it instead. Bounded, and stopped as soon as nothing is
  /// pending, so a backend with no worker running costs one short burst of
  /// polling rather than a permanent one.
  Future<void> _watchAnalysis(CalendarDate date, int generation) async {
    if (state.entries.every((entry) => !entry.analysisPending)) return;

    var waited = Duration.zero;
    while (waited < _analysisPollTimeout) {
      await delay(_analysisPollInterval);
      waited += _analysisPollInterval;
      if (generation != _generation || state.date != date) return;

      try {
        final entries = await ref.read(entriesApiProvider).listByDate(date);
        if (generation != _generation || state.date != date) return;
        state = state.copyWith(entries: entries);
        if (entries.every((entry) => !entry.analysisPending)) return;
      } on ApiError {
        // Keep waiting; the next poll is the retry.
      }
    }
  }

  /// Clears [TodayState.errorMessage] once it has been shown.
  void dismissError() => state = state.copyWith(errorMessage: null);
}

/// The state behind the Today screen.
final todayControllerProvider = NotifierProvider<TodayController, TodayState>(
  TodayController.new,
);
