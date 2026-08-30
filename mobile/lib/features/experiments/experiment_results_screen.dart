import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diary/experiment.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/journal_page_wash.dart';
import '../../core/widgets/status_views.dart';
import 'comparison_bars.dart';
import 'experiment_results_controller.dart';

/// One experiment's results (R-3b): the two-window comparison, the
/// deterministic verdict, and the actions available while it stands --
/// abandon while it is still running, or leave once it is settled.
///
/// Doubles as the "so far" view for an experiment still in progress: the
/// active-experiment banner on Today opens this same screen, and
/// `GET /experiments/{id}/results` already reads the elapsed window rather
/// than the planned one for an experiment that has not finished yet
/// (`experiment-math.ts`'s `elapsedWindow`) -- there is no second, separate
/// "in progress" layout to keep in sync with this one.
class ExperimentResultsScreen extends ConsumerStatefulWidget {
  /// Shows the results for experiment [experimentId].
  ///
  /// [onClose] is a plain callback rather than a direct `go_router`
  /// dependency, matching every other pushed detail screen in this app.
  /// Defaults to popping the route.
  const ExperimentResultsScreen({
    super.key,
    required this.experimentId,
    this.onClose,
  });

  /// The experiment this screen shows.
  final String experimentId;

  /// Called when the user asks to leave this screen. Defaults to
  /// `context.pop()`.
  final VoidCallback? onClose;

  @override
  ConsumerState<ExperimentResultsScreen> createState() =>
      _ExperimentResultsScreenState();
}

class _ExperimentResultsScreenState
    extends ConsumerState<ExperimentResultsScreen> {
  bool _isAbandoning = false;

  void _close() {
    if (widget.onClose case final onClose?) {
      onClose();
      return;
    }
    context.pop();
  }

  void _showError(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Abandon is always available while an experiment is active, one tap
  /// plus a confirmation and nothing more -- no guilt copy, no reason
  /// asked for.
  Future<void> _confirmAbandon() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abandon this experiment?'),
        content: const Text('You can start another one any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Abandon'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    setState(() => _isAbandoning = true);
    try {
      await ref
          .read(
            experimentResultsControllerProvider(widget.experimentId).notifier,
          )
          .abandon();
    } on ApiError catch (error) {
      if (!mounted) return;
      _showError(_messageFor(error));
    } finally {
      if (mounted) setState(() => _isAbandoning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      experimentResultsControllerProvider(widget.experimentId),
    );
    final data = async.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Experiment'),
        backgroundColor: Colors.transparent,
        // `tooltip` alone would only reach the semantics tree's `tooltip`
        // field, not its `label` -- the accessible name a screen reader
        // announces -- so this replaces `IconButton`'s own semantics with
        // an explicit one (the same pattern `pattern_echo_panel.dart`'s
        // dismiss button uses).
        leading: Semantics(
          container: true,
          button: true,
          label: 'Back',
          onTap: _close,
          child: ExcludeSemantics(
            child: IconButton(
              onPressed: _close,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: JournalPageWash()),
          SafeArea(
            child: data == null
                ? _FirstLoadState(
                    async: async,
                    onRetry: () => unawaited(
                      ref
                          .read(
                            experimentResultsControllerProvider(
                              widget.experimentId,
                            ).notifier,
                          )
                          .refresh(),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      JournalSpacing.x4,
                      JournalSpacing.x4,
                      JournalSpacing.x4,
                      JournalSpacing.x7,
                    ),
                    children: [
                      _Content(
                        results: data,
                        isAbandoning: _isAbandoning,
                        onAbandon: () => unawaited(_confirmAbandon()),
                        onDone: _close,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _FirstLoadState extends StatelessWidget {
  const _FirstLoadState({required this.async, required this.onRetry});

  final AsyncValue<ExperimentResults> async;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (async.error case final ApiError error) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: JournalSpacing.x7),
        child: ErrorView(message: _messageFor(error), onRetry: onRetry),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: JournalSpacing.x7),
      child: LoadingView(),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.results,
    required this.isAbandoning,
    required this.onAbandon,
    required this.onDone,
  });

  final ExperimentResults results;
  final bool isAbandoning;
  final VoidCallback onAbandon;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final experiment = results.experiment;
    final topic = _capitalise(experiment.patternTopic);
    final direction = experiment.hypothesisKind == HypothesisKind.lessOf
        ? 'less'
        : 'more';
    final isActive = experiment.status == ExperimentStatus.active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          eyebrow: const Eyebrow('N-of-1 experiment'),
          title: Text(topic, style: theme.textTheme.headlineSmall),
          actions: [_StatusBadgeFor(status: experiment.status)],
        ),
        const SizedBox(height: JournalSpacing.x4),
        Text(
          'Testing $direction ${experiment.patternTopic} against '
          '${experiment.patternFeeling}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: JournalSpacing.x4),
        // The verdict, at the same weight whichever of the three cases it
        // is -- a clear difference, no difference, or too little data.
        // "Too few entries to be sure" is not a smaller fact than a
        // confident-looking percentage; the app is not in the business of
        // making one read as more important than the other.
        JournalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Verdict'),
              const SizedBox(height: JournalSpacing.x2),
              Text(results.verdictText, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
        const SizedBox(height: JournalSpacing.x4),
        ComparisonBars(
          experimentWindow: results.experimentWindow,
          baselineWindow: results.baselineWindow,
          feelingLabel: experiment.patternFeeling,
        ),
        const SizedBox(height: JournalSpacing.x5),
        if (isActive)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: isAbandoning ? null : onAbandon,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Abandon experiment'),
            ),
          )
        else
          PillButton(onPressed: onDone, child: const Text('Done')),
      ],
    );
  }
}

class _StatusBadgeFor extends StatelessWidget {
  const _StatusBadgeFor({required this.status});

  final ExperimentStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (text, color) = switch (status) {
      ExperimentStatus.active => ('Active', theme.colorScheme.primary),
      ExperimentStatus.finished => (
        'Finished',
        theme.colorScheme.onSurfaceVariant,
      ),
      ExperimentStatus.abandoned => (
        'Abandoned',
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    return StatusBadge(text, contentColor: color);
  }
}

String _capitalise(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

String _messageFor(ApiError error) => switch (error) {
  BackendNotConfigured() => 'Set your server address in Settings.',
  NetworkFailure() => 'Could not reach the server.',
  Unauthorized() => 'Please sign in again.',
  HttpFailure(:final message) => message,
};
