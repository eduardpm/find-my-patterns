import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/experiment.dart';
import '../../core/diary/pattern.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/journal_page_wash.dart';
import '../../core/widgets/journal_scrollbar.dart';
import '../../core/widgets/status_views.dart';
import '../experiments/experiment_setup_sheet.dart';
import 'charts/mood_trend_chart.dart';
import 'insights_controller.dart';
import 'pattern_card.dart';
import 'pattern_ranking.dart';
import 'weak_signal_row.dart';
import 'when_panel.dart';
import 'withdrawal_notice.dart';

/// The screen the whole product exists for: the patterns the backend found
/// in the user's diary, the evidence behind each, and when they happen.
///
/// Every value is displayed as received -- see [PatternCard]'s doc comment
/// for the rule this screen and its children never break. What this file
/// owns is the page: section order, the loading/error/empty states, and
/// when a refetch happens.
class InsightsScreen extends ConsumerStatefulWidget {
  /// Creates the Insights screen.
  const InsightsScreen({super.key, this.onOpenEntry, this.onOpenSettings});

  /// Called with an evidence row's entry id and its date when "Open" is
  /// tapped. Defaults to pushing the entry-detail route -- injectable so a
  /// test can assert the right id and date were passed without a real
  /// router in the tree.
  final void Function(String entryId, CalendarDate entryDate)? onOpenEntry;

  /// Called when a [BackendNotConfigured] failure's "Open Settings" button
  /// is tapped. Defaults to pushing the Settings route.
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();

  /// One [GlobalKey] per pattern id, created lazily and kept for the life of
  /// this state -- what a "Worth trying" tap needs to find and expand the
  /// matching [PatternCard] (R-1). The list is rebuilt as a plain
  /// `ListView(children: ...)`, not `.builder`, so every card already in
  /// [InsightsPageState.patterns] is built up front and its key's
  /// `currentContext` is available the moment this map is read -- there is
  /// no "not scrolled into view yet" case to guard against here.
  final Map<String, GlobalKey<PatternCardState>> _patternCardKeys = {};

  GlobalKey<PatternCardState> _keyFor(String patternId) => _patternCardKeys
      .putIfAbsent(patternId, () => GlobalKey<PatternCardState>());

  /// Whether the Insights tab was active the last time [didChangeDependencies]
  /// ran. Starts null so the very first call -- always fired once on mount,
  /// regardless of visibility -- is never mistaken for a return visit.
  bool? _wasActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(insightsControllerProvider.notifier).refresh());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // go_router's `StatefulShellRoute.indexedStack` wraps each branch in a
    // `TickerMode`, enabled only for the currently active tab. Watching it
    // here is how this screen learns "the Insights tab became visible
    // again" without a `NavigatorObserver`, which would mean reaching into
    // the router this app owns rather than this screen.
    final isActive = TickerMode.valuesOf(context).enabled;
    if (isActive && _wasActive == false) {
      // Deferred past the current frame: `didChangeDependencies` runs while
      // the framework is mid-build, and invalidating a provider synchronously
      // from there trips "setState() called during build" the moment
      // anything is listening for the result.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(ref.read(insightsControllerProvider.notifier).refresh());
        }
      });
    }
    _wasActive = isActive;
  }

  void _openEntry(String entryId, CalendarDate entryDate) {
    if (widget.onOpenEntry case final onOpenEntry?) {
      onOpenEntry(entryId, entryDate);
      return;
    }
    context.push('/entry/$entryId/$entryDate');
  }

  void _openSettings() {
    if (widget.onOpenSettings case final onOpenSettings?) {
      onOpenSettings();
      return;
    }
    context.push('/settings');
  }

  Future<void> _acknowledge() async {
    try {
      await ref
          .read(insightsControllerProvider.notifier)
          .acknowledgeWithdrawals();
    } on ApiError catch (error) {
      if (!mounted) return;
      _showError(_messageFor(error));
    }
  }

  /// R-1's tap-through: scroll to the pattern named by [patternId] (a
  /// recommendation's `patternRef`) and expand its evidence trail in place --
  /// never a new route, per `PatternCard`'s own "expands in place ... never
  /// by navigating elsewhere" rule.
  ///
  /// `currentContext` can be null if the pattern was withdrawn between the
  /// response that produced this recommendation and the tap landing (task
  /// 4's derived-per-request recommendations are exactly what makes that
  /// possible) -- silently doing nothing is the right response, the same way
  /// a stale withdrawal notice would simply not find its pattern either.
  void _openRecommendedPattern(String patternId) {
    final cardContext = _patternCardKeys[patternId]?.currentContext;
    if (cardContext == null) return;
    _patternCardKeys[patternId]?.currentState?.expandEvidence();
    // Deferred a frame so the evidence trail's new height is already laid
    // out before `ensureVisible` measures where the card sits.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          cardContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.1,
        ),
      );
    });
  }

  void _showError(String message) => _showSnack(message);

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens the "Test this pattern" sheet (R-3b). [constants] and
  /// [activeExperiment] both come from the currently-loaded page state --
  /// this sheet never fetches either on its own, since whichever screen
  /// opens it already has them.
  Future<void> _openTestPattern(
    Pattern pattern, {
    required ExperimentConstants constants,
    required Experiment? activeExperiment,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => ExperimentSetupSheet(
      pattern: pattern,
      constants: constants,
      activeExperiment: activeExperiment,
      onStarted: (experiment) {
        unawaited(ref.read(insightsControllerProvider.notifier).refresh());
        if (!mounted) return;
        _showSnack('Experiment started: ${experiment.patternTopic}.');
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Fires only on an actual state transition, never on a plain rebuild --
    // which is exactly "surface the error, then clear it" for free: there
    // is nothing to clear, because nothing re-shows without a new failure.
    //
    // Gated on `next.hasValue`: a failure with no value yet is the first
    // load, already explained in place by `_FirstLoadState`'s `ErrorView`,
    // and toasting it too would say the same thing twice. A failure that
    // does carry a value is a refresh that lost -- the content underneath
    // stays as it was, and the snack bar is the only place that failure is
    // said at all.
    ref.listen<AsyncValue<InsightsPageState>>(insightsControllerProvider, (
      _,
      next,
    ) {
      final error = next.error;
      if (next.hasValue && error is ApiError) {
        _showError(_messageFor(error));
      }
    });
    final insightsAsync = ref.watch(insightsControllerProvider);
    final data = insightsAsync.value;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: JournalPageWash()),
          SafeArea(
            child: JournalScrollbar(
              controller: _scrollController,
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(
                  JournalSpacing.x4,
                  JournalSpacing.x5,
                  JournalSpacing.x4,
                  JournalSpacing.x7,
                ),
                children: [
                  PageHeader(
                    eyebrow: const Eyebrow('What keeps coming up'),
                    title: Text(
                      'Insights',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: JournalSpacing.x5),
                  // A spinner only before the first load has ever
                  // completed -- gated on whether data has ever arrived,
                  // not on whether a fetch happens to be in flight right
                  // now, so a background refresh never flashes a spinner
                  // over content that is already on screen.
                  if (data == null)
                    _FirstLoadState(
                      async: insightsAsync,
                      onRetry: () => unawaited(
                        ref.read(insightsControllerProvider.notifier).refresh(),
                      ),
                      onConfigure: _openSettings,
                    )
                  else
                    _Content(
                      data: data,
                      onOpenEntry: _openEntry,
                      onAcknowledge: () => unawaited(_acknowledge()),
                      onTestPattern: (pattern) => unawaited(
                        _openTestPattern(
                          pattern,
                          constants:
                              data.activeExperiment?.constants ??
                              ExperimentConstants.placeholder,
                          activeExperiment: data.activeExperiment,
                        ),
                      ),
                      keyForPattern: _keyFor,
                      onOpenRecommendation: _openRecommendedPattern,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What shows in place of the page's content before the first fetch has
/// ever resolved: a spinner while it is in flight, or -- so a broken first
/// load is not an infinite spinner -- the shared [ErrorView] once it fails,
/// with "Open Settings" offered only for the one failure a user can fix
/// without leaving the app.
class _FirstLoadState extends StatelessWidget {
  const _FirstLoadState({
    required this.async,
    required this.onRetry,
    required this.onConfigure,
  });

  final AsyncValue<InsightsPageState> async;
  final VoidCallback onRetry;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    if (async.error case final ApiError error) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: JournalSpacing.x7),
        child: ErrorView(
          message: _messageFor(error),
          onRetry: onRetry,
          onConfigure: error is BackendNotConfigured ? onConfigure : null,
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: JournalSpacing.x7),
      child: LoadingView(),
    );
  }
}

/// The page once data has arrived at least once: any withdrawals, the "Worth
/// trying" recommendations, the ranked pattern feed (or the insufficient-data
/// empty state), and the "when" panel -- in that order, because the order is
/// a requirement. See the section-by-section reasoning on
/// [_WithdrawalsSection], [_WorthTryingSection], `rankPatterns`
/// (`pattern_ranking.dart`) and [WhenPanel].
class _Content extends StatelessWidget {
  const _Content({
    required this.data,
    required this.onOpenEntry,
    required this.onAcknowledge,
    required this.onTestPattern,
    required this.keyForPattern,
    required this.onOpenRecommendation,
  });

  final InsightsPageState data;
  final void Function(String entryId, CalendarDate entryDate) onOpenEntry;
  final VoidCallback onAcknowledge;
  final void Function(Pattern pattern) onTestPattern;

  /// Looks up (creating on first use) the [GlobalKey] a given pattern id's
  /// [PatternCard] renders under -- what lets [onOpenRecommendation] find and
  /// expand the right card without this widget itself holding any state.
  final GlobalKey<PatternCardState> Function(String patternId) keyForPattern;

  /// Called with a recommendation's `patternRef` when a "Worth trying" card
  /// is tapped (R-1).
  final void Function(String patternId) onOpenRecommendation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ranking = rankPatterns(data.patterns);
    // R-1: already capped and ordered by the backend (task 1's "cap at top
    // three by lift") -- this widget renders whichever patterns carry one,
    // in the order given, rather than re-deriving the cap or the ranking.
    final recommended = [
      for (final pattern in data.patterns)
        if (pattern.recommendation != null) pattern,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // CH-1: the mood-over-time chart, above even the withdrawal
        // notices -- it is the one thing on this screen that answers "how
        // have I been" at a glance, before any pattern-level detail.
        const MoodTrendChart(),
        const SizedBox(height: JournalSpacing.x4),
        // The one thing a user must never have to notice for themselves is
        // a pattern they were told about quietly going away.
        if (data.withdrawals.isNotEmpty) ...[
          _WithdrawalsSection(
            withdrawals: data.withdrawals,
            newCount: data.newWithdrawalCount,
            onAcknowledge: onAcknowledge,
          ),
          const SizedBox(height: JournalSpacing.x4),
        ],
        // R-1: above the ranked pattern feed, below withdrawals -- the
        // issue's own placement. Absent entirely when nothing qualifies,
        // never an empty shell.
        if (recommended.isNotEmpty) ...[
          _WorthTryingSection(
            patterns: recommended,
            onTap: onOpenRecommendation,
          ),
          const SizedBox(height: JournalSpacing.x4),
        ],
        if (data.insufficientData || data.patterns.isEmpty)
          _InsufficientDataState(constants: data.constants)
        else ...[
          // UX-2: confirmed-lift patterns first, richest first -- see
          // `rankPatterns`' own doc comment for the exact ordering, and
          // `PatternCard`'s for why a "Historical" pattern still renders in
          // full rather than being dropped once its evidence ages out.
          for (final pattern in ranking.confirmed) ...[
            PatternCard(
              key: keyForPattern(pattern.id),
              pattern: pattern,
              constants: data.constants,
              onOpenEntry: onOpenEntry,
              activeExperiment: data.activeExperiment,
              onTestPattern: onTestPattern,
            ),
            const SizedBox(height: JournalSpacing.x4),
          ],
          // The weak tier: an undefined or below-threshold lift, or a
          // neutral-valence feeling with nothing to advise on either way
          // (P0-2). Collapsed to one line each rather than given the same
          // billing as a confirmed pattern -- still on the page, still a
          // tap away from its full evidence, just not competing for the
          // same attention.
          if (ranking.weak.isNotEmpty) ...[
            Text('Weaker signals', style: theme.textTheme.titleLarge),
            const SizedBox(height: JournalSpacing.x2),
            for (final pattern in ranking.weak)
              WeakSignalRow(
                pattern: pattern,
                constants: data.constants,
                onOpenEntry: onOpenEntry,
              ),
          ],
        ],
        if (data.whenInsights case final whenInsights?)
          WhenPanel(insights: whenInsights),
      ],
    );
  }
}

/// "N patterns were withdrawn since you last looked". Acknowledging is a
/// button rather than something that happens by arriving here -- see
/// [InsightsController.acknowledgeWithdrawals].
class _WithdrawalsSection extends StatelessWidget {
  const _WithdrawalsSection({
    required this.withdrawals,
    required this.newCount,
    required this.onAcknowledge,
  });

  final List<Withdrawal> withdrawals;
  final int newCount;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Recently withdrawn',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (newCount > 0)
                Text(
                  '$newCount since you last looked',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: JournalSpacing.x3),
          for (final withdrawal in withdrawals) ...[
            WithdrawalNotice(withdrawal: withdrawal),
            const SizedBox(height: JournalSpacing.x2),
          ],
          if (newCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onAcknowledge,
                child: const Text('Got it'),
              ),
            ),
        ],
      ),
    );
  }
}

/// R-1: up to a handful of patterns whose own badge already reads "keep",
/// surfaced as compact "Worth trying" cards above the ranked pattern feed.
///
/// Tinted with `journal.accent`/`accentContainer` rather than the neutral
/// `JournalCard` surface every pattern card and [_WithdrawalsSection] use --
/// the same accent pairing [PatternCard] already reaches for on its own
/// "Without it" badge -- so this reads as a different *kind* of thing (an
/// action worth considering) without introducing a colour the rest of the
/// screen does not already use. [patterns] arrives already capped and
/// ordered by the backend (task 1's top-three-by-lift rule); this widget
/// never re-sorts or re-slices it.
class _WorthTryingSection extends StatelessWidget {
  const _WorthTryingSection({required this.patterns, required this.onTap});

  /// Patterns carrying a non-null [Pattern.recommendation].
  final List<Pattern> patterns;

  /// Called with the tapped pattern's own id when a card is tapped, so the
  /// caller can scroll to and expand the matching [PatternCard].
  final void Function(String patternId) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journal = context.journalColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JournalSpacing.x4),
      decoration: BoxDecoration(
        color: journal.accentContainer,
        borderRadius: JournalShapes.large,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: journal.accent),
              const SizedBox(width: JournalSpacing.x2),
              Text('Worth trying', style: theme.textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: JournalSpacing.x3),
          for (var index = 0; index < patterns.length; index += 1) ...[
            _RecommendationTile(
              pattern: patterns[index],
              onTap: () => onTap(patterns[index].id),
            ),
            if (index != patterns.length - 1)
              const SizedBox(height: JournalSpacing.x2),
          ],
        ],
      ),
    );
  }
}

/// One compact "Worth trying" card: the action headline, the evidence
/// sentence with its counts, and a tap target -- never a navigation, an
/// expansion of the matching [PatternCard] handled entirely by the caller's
/// [_WorthTryingSection.onTap].
///
/// [Pattern.recommendation]'s [Recommendation.headline] and
/// [Recommendation.sentence] are rendered exactly as received (R-0, task 3):
/// this widget composes no prose of its own, and in particular never turns
/// [Recommendation.actionTopic] back into a sentence -- see
/// [Recommendation]'s own doc comment.
class _RecommendationTile extends StatelessWidget {
  const _RecommendationTile({required this.pattern, required this.onTap});

  final Pattern pattern;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Guarded by the caller ([_WorthTryingSection] only ever receives
    // patterns whose `recommendation` is non-null), so this is a plain
    // unwrap, not a fallback.
    final recommendation = pattern.recommendation!;
    return Material(
      color: Colors.transparent,
      borderRadius: JournalShapes.medium,
      child: InkWell(
        onTap: onTap,
        borderRadius: JournalShapes.medium,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(JournalSpacing.x3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: JournalShapes.medium,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recommendation.headline,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: JournalSpacing.x1),
                    // R-0: this sentence carries its own counts -- there is
                    // no rendering of a recommendation without them.
                    Text(
                      recommendation.sentence,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: JournalSpacing.x2),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsufficientDataState extends StatelessWidget {
  const _InsufficientDataState({required this.constants});

  final EngineConstants constants;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: const Icon(Icons.insights),
    title: const Text('Not enough data yet'),
    supporting: Text(
      'Keep logging entries — once a topic and a feeling repeat at least '
      '${constants.minOccurrenceThreshold} times in the last '
      '${constants.recencyWindowDays} days, the pattern shows up here.',
      textAlign: TextAlign.center,
    ),
  );
}

/// Maps a sealed [ApiError] to user-facing text. Exhaustive by construction
/// -- the compiler flags this switch the day a new [ApiError] subtype is
/// added, which is the whole reason the type is sealed.
String _messageFor(ApiError error) => switch (error) {
  BackendNotConfigured() => 'Set your server address in Settings.',
  NetworkFailure() => 'Could not reach the server.',
  Unauthorized() => 'Please sign in again.',
  HttpFailure(:final message) => message,
};
