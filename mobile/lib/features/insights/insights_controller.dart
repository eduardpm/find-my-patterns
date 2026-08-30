import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diary/diary_providers.dart';
import '../../core/diary/experiment.dart';
import '../../core/diary/insights_api.dart';
import '../../core/diary/pattern.dart';
import '../../core/network/api_error.dart';

/// Everything the Insights screen renders, gathered from the two endpoints
/// it fetches independently.
///
/// [whenInsights] is nullable rather than defaulted to some empty value: a
/// missing "when" panel (its own fetch failed) is a different fact from a
/// panel the backend answered with zero entries in the window, and the
/// screen tells them apart by leaving this null rather than inventing a
/// placeholder.
class const InsightsPageState({
  final List<Pattern> patterns = const [],
  final List<Withdrawal> withdrawals = const [],
  final int newWithdrawalCount = 0,
  final bool insufficientData = false,
  final EngineConstants constants = EngineConstants.placeholder,
  final WhenInsights? whenInsights,

  /// How many days the diary spans (M-3, #48) -- see
  /// [InsightsResult.historySpanDays]. `null` before the first response
  /// lands, the same "never shown as a fact" rule every other placeholder
  /// default on this page follows.
  final int? historySpanDays,

  /// The experiment currently running (R-3b), or `null` when none is.
  /// Fetched alongside `GET /insights`, the same "own independent fetch,
  /// swallowed on failure" shape [whenInsights] already has -- see
  /// [InsightsController._fetchActiveExperiment].
  final Experiment? activeExperiment,
}) {
  /// The patterns still holding within the recency window.
  List<Pattern> get active => [
    for (final pattern in patterns)
      if (pattern.status == PatternStatus.active) pattern,
  ];

  /// The patterns that held once but have aged out of the window -- kept
  /// and marked, never dropped. See [PatternStatus.historical].
  List<Pattern> get historical => [
    for (final pattern in patterns)
      if (pattern.status == PatternStatus.historical) pattern,
  ];
}

/// Holds the state behind the Insights screen: the detected patterns, any
/// pending withdrawals, and the weekday/time-of-day breakdown.
///
/// Two independent fetches make up one page. `GET /insights` is the one
/// this notifier's own [AsyncValue] tracks -- its failure is what turns
/// [insightsControllerProvider] into an [AsyncError], which the screen
/// reads through [Ref.listen] and surfaces as a snack bar. `GET
/// /insights/when` answers a different question and is allowed to fail on
/// its own: a hiccup fetching it leaves [InsightsPageState.whenInsights]
/// absent rather than blanking the patterns already on screen.
class InsightsController extends AsyncNotifier<InsightsPageState> {
  @override
  Future<InsightsPageState> build() => _fetch();

  Future<InsightsPageState> _fetch() async {
    final api = ref.watch(insightsApiProvider);
    final result = await api.insights();
    return InsightsPageState(
      patterns: result.patterns,
      withdrawals: result.withdrawals,
      newWithdrawalCount: result.newWithdrawalCount,
      insufficientData: result.insufficientData,
      constants: result.constants,
      historySpanDays: result.historySpanDays,
      whenInsights: await _fetchWhenInsights(api),
      activeExperiment: await _fetchActiveExperiment(),
    );
  }

  Future<WhenInsights?> _fetchWhenInsights(InsightsApi api) async {
    try {
      return await api.whenInsights();
    } on ApiError {
      return null;
    }
  }

  /// The currently active experiment (R-3b), swallowed to `null` on any
  /// failure -- the same shape [_fetchWhenInsights] already has. A pattern
  /// card's "Test this pattern"/"Experiment running" state is worth
  /// getting wrong for a moment over losing the patterns list to an
  /// unrelated fetch failing.
  Future<Experiment?> _fetchActiveExperiment() async {
    try {
      return await ref.watch(experimentsApiProvider).active();
    } on ApiError {
      return null;
    }
  }

  /// Refetches both endpoints.
  ///
  /// Called on first mount, on `AppLifecycleState.resumed`, when the
  /// Insights tab is revisited, and after acknowledging withdrawals. Goes
  /// through [Ref.invalidateSelf] rather than assigning [state] directly so
  /// a failed refresh keeps whatever content is already on screen -- the
  /// framework carries the previous value forward into the resulting
  /// [AsyncError] itself, which is not something this notifier is allowed
  /// to do by hand (the API that would let it, `copyWithPrevious`, is
  /// internal to Riverpod).
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } on ApiError {
      // Already reflected in `state`; the screen's own listener reports it.
    }
  }

  /// Marks every current withdrawal notice as seen, then refetches.
  ///
  /// A deliberate action rather than a side effect of opening the screen --
  /// if merely arriving here cleared the flag, whichever device the user
  /// opened first would clear it for the other. Deliberately does not catch
  /// a failure of the acknowledgement itself: that is a different action
  /// from the fetch [refresh] guards, and its caller decides how to report
  /// it.
  Future<void> acknowledgeWithdrawals() async {
    await ref.read(insightsApiProvider).acknowledgeWithdrawals();
    await refresh();
  }
}

/// The state behind the Insights screen.
///
/// Retries are turned off: Riverpod's default policy retries a failed build
/// silently, up to ten times over roughly forty seconds, and none of
/// [ApiError]'s subtypes are a Dart [Error] so every one of them qualifies
/// by default. A user staring at a spinner for forty seconds before ever
/// seeing the failure is worse than seeing it at once and tapping refresh.
final insightsControllerProvider =
    AsyncNotifierProvider<InsightsController, InsightsPageState>(
      InsightsController.new,
    );
