import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diary/diary_providers.dart';
import '../../core/diary/experiment.dart';
import '../../core/diary/pattern.dart';
import '../../core/network/api_error.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/premium_lock.dart';

/// "Test this pattern": the setup sheet a pattern card opens (R-3b).
///
/// Phrases the hypothesis from [pattern] -- never asks the reader to word
/// it themselves -- offers the length picker (default and range read from
/// [constants], never hardcoded), and starts the experiment through
/// `POST /experiments`.
///
/// Eligibility is entirely the backend's call (point 1 of R-3b): this sheet
/// never checks [pattern]'s kind, status or lift before offering the
/// action, and a non-qualifying pattern's 422 rejection is shown exactly as
/// [ApiError] renders it everywhere else in this app, not pre-empted by a
/// second copy of the rule `experiments.service.ts` already enforces.
///
/// [activeExperiment] is the one already running, if any -- passed in
/// rather than fetched again here, since whichever screen opened this
/// sheet already knows it. A non-null value always blocks a plain start
/// (the single-active constraint, point 2): the sheet offers to abandon it
/// first instead of sending a request the backend would refuse anyway.
class ExperimentSetupSheet extends ConsumerStatefulWidget {
  /// Opens the sheet for [pattern].
  const ExperimentSetupSheet({
    super.key,
    required this.pattern,
    required this.constants,
    required this.activeExperiment,
    required this.onStarted,
  });

  /// The pattern this experiment tests.
  final Pattern pattern;

  /// The length picker's default and range.
  final ExperimentConstants constants;

  /// The currently active experiment, if any.
  final Experiment? activeExperiment;

  /// Called with the newly created experiment once `POST /experiments`
  /// succeeds -- the caller's cue to refresh its own state and let the
  /// reader know it started.
  final ValueChanged<Experiment> onStarted;

  @override
  ConsumerState<ExperimentSetupSheet> createState() =>
      _ExperimentSetupSheetState();
}

class _ExperimentSetupSheetState extends ConsumerState<ExperimentSetupSheet> {
  late int _lengthDays = widget.constants.defaultLengthDays;
  bool _isSubmitting = false;
  String? _errorMessage;

  /// M-3, #48: `POST /experiments` answered `premium_required`.
  ///
  /// `PatternCard` already keeps a free account from reaching this sheet at
  /// all -- its "Test this pattern" action is replaced by an Upgrade prompt
  /// before this sheet ever opens. This flag is the defensive second layer
  /// for the one way that guard can still be stale: the account's tier
  /// lapsed between this sheet opening and the tap on Start (exactly what
  /// the orchestrator's manual tier-flip demo exercises). Task 4's own
  /// words -- "a request that comes back `premium_required` should surface
  /// the locked state, not an error snackbar" -- apply here too, so this
  /// gets its own flag rather than folding into [_errorMessage] and being
  /// rendered as backend prose a moment after the sheet insisted the
  /// account could start one.
  bool _premiumRequired = false;

  /// A `change`-badged pattern (the topic is worth cutting back on) is
  /// tested by doing less of it; a `keep`-badged one, by doing more.
  /// `PatternCard` only ever offers this sheet from the confirmed tier,
  /// where [Pattern.direction] is always one of these two (never `none` --
  /// see `rankPatterns`), so there is no third case to phrase.
  HypothesisKind get _hypothesisKind =>
      widget.pattern.direction == PatternDirection.change
      ? HypothesisKind.lessOf
      : HypothesisKind.moreOf;

  String get _directionWord =>
      _hypothesisKind == HypothesisKind.lessOf ? 'less' : 'more';

  String get _hypothesisText {
    final feeling = widget.pattern.feeling;
    final feelingLabel = feeling?.label.toLowerCase() ?? 'this feeling';
    return 'Try $_directionWord ${widget.pattern.topic} for the next '
        '$_lengthDays days and see what happens to $feelingLabel.';
  }

  void _changeLength(int delta) {
    final next = (_lengthDays + delta).clamp(
      widget.constants.minLengthDays,
      widget.constants.maxLengthDays,
    );
    if (next == _lengthDays) return;
    setState(() => _lengthDays = next);
  }

  Future<void> _start() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _premiumRequired = false;
    });
    try {
      final experiment = await ref
          .read(experimentsApiProvider)
          .create(
            patternTopic: widget.pattern.topic,
            patternFeeling: widget.pattern.feeling?.key ?? '',
            hypothesisKind: _hypothesisKind,
            lengthDays: _lengthDays,
          );
      // Not an entry write, but the same "something elsewhere may have
      // changed" fact Today's own copy of the active experiment already
      // listens for -- see `TodayController._loadActiveExperiment`.
      ref.read(diaryWriteSignalProvider.notifier).bump();
      if (!mounted) return;
      widget.onStarted(experiment);
      Navigator.of(context).pop();
    } on ApiError catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        if (isPremiumRequired(error)) {
          _premiumRequired = true;
        } else {
          _errorMessage = _messageFor(error);
        }
      });
    }
  }

  /// The single-active conflict (point 2): abandons [Experiment] currently
  /// running, then starts this one. One combined action rather than two
  /// separate taps -- the reader has already said what they want by
  /// pressing it.
  Future<void> _abandonAndStart() async {
    final blocking = widget.activeExperiment;
    if (blocking == null) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _premiumRequired = false;
    });
    try {
      await ref.read(experimentsApiProvider).abandon(blocking.id);
      final experiment = await ref
          .read(experimentsApiProvider)
          .create(
            patternTopic: widget.pattern.topic,
            patternFeeling: widget.pattern.feeling?.key ?? '',
            hypothesisKind: _hypothesisKind,
            lengthDays: _lengthDays,
          );
      ref.read(diaryWriteSignalProvider.notifier).bump();
      if (!mounted) return;
      widget.onStarted(experiment);
      Navigator.of(context).pop();
    } on ApiError catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        if (isPremiumRequired(error)) {
          _premiumRequired = true;
        } else {
          _errorMessage = _messageFor(error);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journal = context.journalColors;
    final blocking = widget.activeExperiment;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          JournalSpacing.x4,
          JournalSpacing.x4,
          JournalSpacing.x4,
          JournalSpacing.x4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Test this pattern', style: theme.textTheme.titleLarge),
            const SizedBox(height: JournalSpacing.x3),
            Text(_hypothesisText, style: theme.textTheme.bodyLarge),
            const SizedBox(height: JournalSpacing.x4),
            // M-3, #48: a lapsed tier answers this exact sheet's own
            // request, not a hypothetical elsewhere -- so it takes priority
            // over the single-active conflict below. Reaching this is rare
            // (see [_premiumRequired]'s own doc comment), but when it
            // happens there is nothing this sheet can still offer: not the
            // length picker, and not "abandon and start instead" either,
            // since starting a replacement would fail exactly the same way.
            if (_premiumRequired) ...[
              PremiumLock(
                message: 'Experiments are a Premium feature.',
                onUpgrade: () => context.push('/upgrade'),
              ),
              const SizedBox(height: JournalSpacing.x4),
            ] else ...[
              if (blocking != null) ...[
                Text(
                  'An experiment is already running: '
                  '${blocking.patternTopic}. Only one can run at a time.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: journal.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: JournalSpacing.x4),
              ] else ...[
                _LengthPicker(
                  lengthDays: _lengthDays,
                  constants: widget.constants,
                  onChange: _isSubmitting ? null : _changeLength,
                ),
                const SizedBox(height: JournalSpacing.x4),
              ],
              if (_errorMessage case final message?) ...[
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: JournalSpacing.x3),
              ],
              SizedBox(
                width: double.infinity,
                child: PillButton(
                  onPressed: _isSubmitting
                      ? null
                      : (blocking != null ? _abandonAndStart : _start),
                  child: Text(
                    blocking != null
                        ? 'Abandon it and start this instead'
                        : 'Start',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LengthPicker extends StatelessWidget {
  const _LengthPicker({
    required this.lengthDays,
    required this.constants,
    required this.onChange,
  });

  final int lengthDays;
  final ExperimentConstants constants;

  /// Called with the delta (`-1`/`+1`) to apply, or `null` while disabled.
  final void Function(int delta)? onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text('Length', style: theme.textTheme.labelLarge),
        ),
        _StepButton(
          icon: Icons.remove,
          description: 'Fewer days',
          onPressed: lengthDays <= constants.minLengthDays || onChange == null
              ? null
              : () => onChange!(-1),
        ),
        SizedBox(
          width: 72,
          child: Text(
            '$lengthDays days',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        _StepButton(
          icon: Icons.add,
          description: 'More days',
          onPressed: lengthDays >= constants.maxLengthDays || onChange == null
              ? null
              : () => onChange!(1),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.description,
    required this.onPressed,
  });

  final IconData icon;
  final String description;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: JournalSpacing.x7,
    height: JournalSpacing.x7,
    child: Semantics(
      label: description,
      button: true,
      enabled: onPressed != null,
      child: ExcludeSemantics(
        child: IconButton(onPressed: onPressed, icon: Icon(icon)),
      ),
    ),
  );
}

String _messageFor(ApiError error) => switch (error) {
  BackendNotConfigured() => 'Set your server address in Settings.',
  NetworkFailure() => 'Could not reach the server.',
  Unauthorized() => 'Please sign in again.',
  HttpFailure(:final message) => message,
};
