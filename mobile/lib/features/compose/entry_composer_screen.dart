import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/audio/diary_audio_recorder.dart';
import '../../core/diary/calendar_date.dart';
import '../../core/diary/entry.dart';
import '../../core/diary/feeling.dart';
import '../../core/diary/pattern.dart';
import '../../core/notifications/reminder_providers.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/theme/journal_typography.dart';
import '../../core/widgets/feeling_chips.dart';
import '../../core/widgets/intensity_dial.dart';
import '../../core/widgets/journal.dart';
import '../../core/widgets/journal_page_wash.dart';
import '../../core/widgets/pattern_echo_panel.dart';
import 'entry_composer_controller.dart';
import 'first_pattern_card.dart';
import 'guided_question_flow.dart';
import 'voice_answer_recorder.dart';

/// The time-of-day shown in the restored-draft notice, e.g. "11:32 PM".
final DateFormat _draftTimeFormat = DateFormat.jm();

/// The date shown in the "Writing about…" header chip, e.g. "Wednesday,
/// August 26".
final DateFormat _targetDateFormat = DateFormat('EEEE, MMMM d');

/// The entry composer: a four-stage flow for writing a diary entry, from
/// the first prompt to the confirmed feeling and any pattern the diary
/// already has to say about it.
///
/// The stages are [GuidedStage], [FreeformStage], [ConfirmFeelingStage] and
/// [EchoStage] — see `entry_composer_controller.dart`'s [ComposerStage] for
/// what each means and why they are ordered the way they are.
class EntryComposerScreen extends ConsumerWidget {
  /// Builds the composer. [onDone] and [onCancel] default to popping this
  /// screen off the navigation stack; a caller that needs to route
  /// somewhere else — or a test that wants to observe the call rather than
  /// depend on a real [Navigator] — passes its own.
  const EntryComposerScreen({
    super.key,
    this.targetDate,
    this.onDone,
    this.onCancel,
    this.recorder,
    this.transcriptionDelay = Future.delayed,
  });

  /// The calendar day this composer writes for (#36) -- null (the default)
  /// means today. The two backdating entry points (the day view's empty
  /// state, and the Today nudge) pass an explicit past date instead; the
  /// app's router resolves this from the `/compose` route's own `date`
  /// query parameter.
  final CalendarDate? targetDate;

  /// Called once the entry is fully saved and there is nothing more to
  /// show — either straight from [ConfirmFeelingStage] (nothing to echo),
  /// or from [EchoStage]'s own "Done" button.
  final VoidCallback? onDone;

  /// Called when the composer is abandoned before an entry is saved.
  final VoidCallback? onCancel;

  /// The recorder every step's voice button uses. Defaults to the real
  /// device microphone; a test injects one built over a fake plugin.
  final DiaryAudioRecorder? recorder;

  /// Injected into every voice recorder's transcription poll loop, so a
  /// test never waits on a real clock.
  final Future<void> Function(Duration) transcriptionDelay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = targetDate ?? CalendarDate.today();
    final state = ref.watch(entryComposerControllerProvider(date));
    final controller = ref.read(entryComposerControllerProvider(date).notifier);
    final done = onDone ?? () => Navigator.of(context).maybePop();
    // Not `maybePop` -- see [requestCancel]'s doc comment for why the
    // default has to be the unconditional `pop`.
    final cancel = onCancel ?? () => Navigator.of(context).pop();

    ref.listen(
      entryComposerControllerProvider(date).select((s) => s.errorMessage),
      (previous, next) {
        if (next == null) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next)));
        controller.dismissError();
      },
    );

    // X and system back both funnel through here rather than calling
    // [cancel] directly: whichever one is pressed, the answer to "does
    // this need the guard sheet" has to come from the same read of
    // `ComposerState.hasUnsavedComposition`, taken fresh at the moment of
    // the tap -- not captured once at the top of `build` -- so a
    // keystroke in between two taps is never judged against a stale
    // snapshot.
    //
    // [cancel]'s default calls `Navigator.pop` (unconditional), never
    // `maybePop`. `maybePop` consults this same route's `canPop` -- which
    // [PopScope] below sets to false for exactly the window this function
    // is asking "should I intercept?" -- and that value only updates on
    // this widget's *next* build. Discarding sets `ComposerState` back to
    // empty and calls `cancel()` in the same breath, well before that
    // rebuild lands, so a `maybePop`-based default would still see the
    // stale `false`, get intercepted by the very `PopScope` it is trying
    // to get past, and call straight back into this function -- forever.
    // `pop` bypasses `canPop` entirely, the same way Flutter's own PopScope
    // examples finish a confirmed pop, so this always actually leaves.
    Future<void> requestCancel() async {
      if (!ref
          .read(entryComposerControllerProvider(date))
          .hasUnsavedComposition) {
        cancel();
        return;
      }
      final discard = await showModalBottomSheet<bool>(
        context: context,
        builder: (sheetContext) => const _DiscardEntrySheet(),
      );
      // A sheet dismissed by tapping outside it or by the system back
      // gesture comes back null -- the same as "Keep writing": nothing
      // more to do, the composer is exactly as it was.
      if (discard ?? false) {
        await controller.discardDraft();
        if (!context.mounted) return;
        cancel();
      }
    }

    return PopScope<void>(
      // Dynamic, not a blanket `false`: once there is nothing left to lose
      // (an empty composer, or the entry already safely stored on
      // [ConfirmFeelingStage]/[EchoStage] -- see
      // `ComposerState.hasUnsavedComposition`), a system back gesture, and
      // `done`'s own `maybePop`, must succeed on the first try rather than
      // being intercepted just to immediately re-approve themselves.
      canPop: !state.hasUnsavedComposition,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(requestCancel());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New entry'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: () => unawaited(requestCancel()),
          ),
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: JournalPageWash()),
            Padding(
              padding: const EdgeInsets.all(JournalSpacing.x5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.isBackdated) ...[
                    _TargetDateChip(date: state.targetDate),
                    const SizedBox(height: JournalSpacing.x4),
                  ],
                  if (state.restoredDraftAt case final savedAt?) ...[
                    _RestoredDraftNotice(
                      savedAt: savedAt,
                      onDismiss: controller.dismissDraftNotice,
                      onStartFresh: () => unawaited(controller.discardDraft()),
                    ),
                    const SizedBox(height: JournalSpacing.x4),
                  ],
                  Expanded(
                    child: switch (state.stage) {
                      GuidedStage() => GuidedQuestionFlow(
                        library: state.guidingQuestions,
                        answers: state.guidedAnswers,
                        stepIndex: state.guidedStepIndex,
                        onAnswerChange: controller.updateGuidedAnswer,
                        onStepChange: controller.updateGuidedStep,
                        onBypassToFreeform: controller.switchToFreeform,
                        onComplete: controller.saveGuided,
                        recorder: recorder,
                        transcriptionDelay: transcriptionDelay,
                      ),
                      FreeformStage() => _FreeformStep(
                        text: state.freeformText,
                        onTextChange: controller.updateFreeformText,
                        onBackToGuided: controller.switchToGuided,
                        onSave: controller.saveFreeform,
                        isSaving: state.isSaving,
                        recorder: recorder,
                        transcriptionDelay: transcriptionDelay,
                      ),
                      ConfirmFeelingStage(:final entry) => _ConfirmFeelingStep(
                        entry: entry,
                        groups: state.feelingGroups,
                        constants: state.constants,
                        isSaving: state.isSaving,
                        isPollingSuggestions: state.isPollingSuggestions,
                        onConfirm: (feelings, intensities) async {
                          final finished = await controller.confirmFeelings(
                            entryId: entry.id,
                            version: entry.version,
                            feelings: feelings,
                            intensities: intensities,
                          );
                          if (finished) done();
                        },
                      ),
                      EchoStage(:final echoes, :final celebratedPattern) =>
                        _EchoStep(
                          echoes: echoes,
                          celebratedPattern: celebratedPattern,
                          onDone: done,
                          onCelebrationTap: () {
                            // Same destination a tap on the first-pattern
                            // notification reaches (#38) -- one signal, one
                            // `app.dart` listener, whether the tap came
                            // from this in-app card or from the OS.
                            ref
                                .read(openInsightsSignalProvider.notifier)
                                .bump();
                            done();
                          },
                        ),
                    },
                  ),
                ],
              ),
            ),
            if (state.isSaving && state.stage is! ConfirmFeelingStage)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Writing about Wednesday, August 26" -- a quiet header chip shown only
/// while [ComposerState.isBackdated], so a composer opened for a past date
/// never lets which day it will land on go unstated (#36). Present through
/// every stage of the flow, confirm and echo included, for the same reason:
/// which day this entry lands on stays worth knowing until the entry is
/// actually saved.
class _TargetDateChip extends StatelessWidget {
  const _TargetDateChip({required this.date});

  final CalendarDate date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: JournalShapes.full,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: JournalSpacing.x3,
            vertical: JournalSpacing.x2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: JournalSpacing.x2),
              Text(
                'Writing about ${_targetDateFormat.format(date.toDateTime())}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Discard this entry?" -- shown when X or system back is pressed while
/// [ComposerState.hasUnsavedComposition] is true.
///
/// `Keep writing` is the default: it is the filled, more prominent button,
/// and it is also what tapping outside the sheet or pressing back again
/// does, since both come back from `showModalBottomSheet` as null. `Discard`
/// is styled destructive -- the error colour, not just a plain text
/// button -- so the two are never confusable at a glance.
class _DiscardEntrySheet extends StatelessWidget {
  const _DiscardEntrySheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(JournalSpacing.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Discard this entry?', style: theme.textTheme.titleLarge),
            const SizedBox(height: JournalSpacing.x2),
            Text(
              "What you've written so far will be lost.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: JournalSpacing.x5),
            PillButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep writing'),
            ),
            const SizedBox(height: JournalSpacing.x3),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('Discard'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Continuing your draft from 11:32 PM — Start fresh" -- shown once, at
/// the top of the composer, when [EntryComposerController] restored a
/// draft on this open. Dismissible on its own (the `x`) without touching
/// the restored answers; `Start fresh` discards them instead.
class _RestoredDraftNotice extends StatelessWidget {
  const _RestoredDraftNotice({
    required this.savedAt,
    required this.onDismiss,
    required this.onStartFresh,
  });

  final DateTime savedAt;
  final VoidCallback onDismiss;
  final VoidCallback onStartFresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: JournalShapes.medium,
      child: Padding(
        padding: const EdgeInsets.only(
          left: JournalSpacing.x4,
          right: JournalSpacing.x1,
        ),
        child: Row(
          children: [
            Expanded(
              // `Wrap` rather than one `Text` -- the "Start fresh" action
              // is a real button (a focusable, screen-reader-visible
              // control with a sensible touch target), not text with a
              // tap recognizer glued on, so it has to sit beside the
              // sentence rather than inside it.
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Continuing your draft from '
                    '${_draftTimeFormat.format(savedAt.toLocal())}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    onPressed: onStartFresh,
                    child: const Text('Start fresh'),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Dismiss',
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

/// Freeform writing: one text field, the voice recorder, and the way back
/// to guided questions.
class _FreeformStep extends StatefulWidget {
  const _FreeformStep({
    required this.text,
    required this.onTextChange,
    required this.onBackToGuided,
    required this.onSave,
    required this.isSaving,
    required this.recorder,
    required this.transcriptionDelay,
  });

  final String text;
  final ValueChanged<String> onTextChange;
  final VoidCallback onBackToGuided;
  final ValueChanged<String> onSave;
  final bool isSaving;
  final DiaryAudioRecorder? recorder;
  final Future<void> Function(Duration) transcriptionDelay;

  @override
  State<_FreeformStep> createState() => _FreeformStepState();
}

class _FreeformStepState extends State<_FreeformStep> {
  // Saving while a recording is still being transcribed would drop those
  // words.
  bool _voiceBusy = false;

  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(covariant _FreeformStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keeps the field in sync with an externally-seeded or voice-appended
    // draft -- `TextFormField`'s own `initialValue` only applies on its
    // first build, so a later change to [widget.text] would otherwise be
    // silently ignored once the field has mounted.
    if (widget.text != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave =
        widget.text.trim().isNotEmpty && !widget.isSaving && !_voiceBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Eyebrow('Freeform'),
        const SizedBox(height: JournalSpacing.x1),
        Text("What's going on?", style: theme.textTheme.headlineSmall),
        const SizedBox(height: JournalSpacing.x5),
        Expanded(
          child: TextFormField(
            controller: _controller,
            onChanged: widget.onTextChange,
            expands: true,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: JournalType.prose,
            decoration: const InputDecoration(
              hintText: "Write whatever's on your mind…",
              border: OutlineInputBorder(borderRadius: JournalShapes.medium),
              alignLabelWithHint: true,
            ),
          ),
        ),
        const SizedBox(height: JournalSpacing.x4),
        VoiceAnswerRecorder(
          onTranscript: (transcript) {
            final existing = widget.text.trim();
            widget.onTextChange(
              existing.isEmpty ? transcript : '$existing $transcript',
            );
          },
          onBusyChange: (busy) => setState(() => _voiceBusy = busy),
          recorder: widget.recorder,
          transcriptionDelay: widget.transcriptionDelay,
        ),
        const SizedBox(height: JournalSpacing.x3),
        SecondaryPillButton(
          onPressed: widget.onBackToGuided,
          child: const Text('Use guided questions instead'),
        ),
        const SizedBox(height: JournalSpacing.x3),
        PillButton(
          onPressed: canSave ? () => widget.onSave(widget.text) : null,
          child: Text(widget.isSaving ? 'Saving…' : 'Save entry'),
        ),
      ],
    );
  }
}

/// "How did that feel?" — feeling and intensity confirmation, seeded from
/// the analyser's suggestion.
class _ConfirmFeelingStep extends StatefulWidget {
  const _ConfirmFeelingStep({
    required this.entry,
    required this.groups,
    required this.constants,
    required this.isSaving,
    required this.isPollingSuggestions,
    required this.onConfirm,
  });

  final Entry entry;
  final List<FeelingGroup> groups;
  final EngineConstants constants;
  final bool isSaving;

  /// True while the analyser's verdict is still being polled for -- see
  /// `EntryComposerController._pollForSuggestions`. Shows a lightweight
  /// "Reading your entry…" banner without disabling anything: the manual
  /// picker below is fully usable the whole time, so someone who would
  /// rather just pick is never made to wait on the worker.
  final bool isPollingSuggestions;
  final void Function(List<Feeling> feelings, Map<String, int> intensities)
  onConfirm;

  @override
  State<_ConfirmFeelingStep> createState() => _ConfirmFeelingStepState();
}

class _ConfirmFeelingStepState extends State<_ConfirmFeelingStep> {
  late List<Feeling> _selected = _seedSelected();
  late Map<String, int> _intensities = Map.of(widget.entry.feelingIntensities);

  List<Feeling> _seedSelected() {
    final suggested = [
      for (final suggestion in widget.entry.suggestedFeelings)
        suggestion.feeling,
    ];
    return suggested.isNotEmpty ? suggested : widget.entry.feelings;
  }

  @override
  void didUpdateWidget(covariant _ConfirmFeelingStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-seed when the vocabulary arrives (empty groups -> non-empty), so a
    // picker composed before `GET /feelings` returned does not stay empty,
    // and when the entry itself changes.
    final vocabularyArrived =
        oldWidget.groups.isEmpty && widget.groups.isNotEmpty;
    if (widget.entry.id != oldWidget.entry.id || vocabularyArrived) {
      setState(() {
        _selected = _seedSelected();
        _intensities = Map.of(widget.entry.feelingIntensities);
      });
      return;
    }

    // The analyser's suggestion can land after this step is already on
    // screen -- see `EntryComposerController._pollForSuggestions` -- as a
    // later build carrying the *same* entry id with `suggestedFeelings` now
    // populated. Pre-select it, but only while nothing has been chosen yet:
    // once the picker holds a manual pick (or an earlier suggestion the
    // user already edited), a late-arriving suggestion must not clobber it.
    final suggestionsArrived =
        oldWidget.entry.suggestedFeelings.isEmpty &&
        widget.entry.suggestedFeelings.isNotEmpty;
    if (suggestionsArrived && _selected.isEmpty) {
      setState(() => _selected = _seedSelected());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggested = widget.entry.suggestedFeelings;
    final subtitle = suggested.isEmpty
        ? 'How would you describe how you felt?'
        : "It sounds like you're feeling "
              '${_joinToPhrase([
                for (final s in suggested) s.feeling.label.toLowerCase(),
              ])}. Confirm that, or pick differently.';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: JournalSpacing.x6),
          const Eyebrow('Saved'),
          const SizedBox(height: JournalSpacing.x1),
          Text('How did that feel?', style: theme.textTheme.headlineSmall),
          const SizedBox(height: JournalSpacing.x2),
          if (widget.isPollingSuggestions) ...[
            const _ReadingEntryBanner(),
            const SizedBox(height: JournalSpacing.x2),
          ],
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: JournalSpacing.x5),
          FeelingChips(
            groups: widget.groups,
            selected: _selected,
            onSelectionChange: (next) {
              setState(() {
                _selected = next;
                final remaining = {for (final f in next) f.key};
                // Unpicking a feeling drops its intensity: a rating belongs
                // to its feeling, so removing a word takes its number with
                // it rather than leaving it for whichever word lands there
                // next.
                _intensities = {
                  for (final entry in _intensities.entries)
                    if (remaining.contains(entry.key)) entry.key: entry.value,
                };
              });
            },
            suggestedKeys: {for (final s in suggested) s.feeling.key},
          ),
          const SizedBox(height: JournalSpacing.x4),
          // After the feelings and never before them.
          IntensityDials(
            feelings: _selected,
            intensities: _intensities,
            onChange: (feeling, value) {
              setState(() {
                if (value == null) {
                  _intensities = {..._intensities}..remove(feeling.key);
                } else {
                  _intensities = {..._intensities, feeling.key: value};
                }
              });
            },
            min: widget.constants.minIntensity,
            max: widget.constants.maxIntensity,
          ),
          const SizedBox(height: JournalSpacing.x5),
          SizedBox(
            width: double.infinity,
            child: PillButton(
              onPressed: !widget.isSaving && _selected.isNotEmpty
                  ? () => widget.onConfirm(_selected, _intensities)
                  : null,
              child: Text(widget.isSaving ? 'Saving…' : 'Confirm'),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Reading your entry…" -- shown above the manual picker while
/// [EntryComposerController] polls for the analyser's verdict.
///
/// A status line beside the picker, not a screen that replaces it: the
/// manual picker is never blocked on this, so this is decoration for
/// someone willing to wait a moment, not a gate for someone who isn't.
/// Announced as a live region for the same reason
/// `VoiceAnswerRecorder`'s status text is -- the wait is silent otherwise.
class _ReadingEntryBanner extends StatelessWidget {
  const _ReadingEntryBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: 'Reading your entry…',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: JournalSpacing.x2),
            Text(
              'Reading your entry…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `[a]` -> "a"; `[a, b]` -> "a and b"; `[a, b, c]` -> "a, b and c".
String _joinToPhrase(List<String> words) => switch (words.length) {
  0 => '',
  1 => words.first,
  _ => '${words.sublist(0, words.length - 1).join(', ')} and ${words.last}',
};

/// What the diary already had to say, shown once the entry and its feeling
/// are both settled.
class _EchoStep extends StatelessWidget {
  const _EchoStep({
    required this.echoes,
    required this.onDone,
    this.celebratedPattern,
    this.onCelebrationTap,
  });

  final List<PatternEcho> echoes;
  final VoidCallback onDone;

  /// The diary's first pattern, when this save is what surfaced it
  /// (L-3/#38) and the app was in the foreground to show it inline instead
  /// of as a notification. Null on every other save.
  final Pattern? celebratedPattern;

  /// Called when the first-pattern card is tapped. Only read when
  /// [celebratedPattern] is set; falls back to [onDone] so this step never
  /// renders a dead tap target if a caller ever supplies one without the
  /// other.
  final VoidCallback? onCelebrationTap;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: JournalSpacing.x6),
        const Eyebrow('Saved'),
        const SizedBox(height: JournalSpacing.x1),
        Text(
          'Entry saved',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: JournalSpacing.x5),
        if (celebratedPattern case final pattern?) ...[
          FirstPatternCard(
            pattern: pattern,
            onTap: onCelebrationTap ?? onDone,
          ),
          const SizedBox(height: JournalSpacing.x5),
        ],
        PatternEchoPanel(echoes: echoes, onDismiss: onDone),
        const SizedBox(height: JournalSpacing.x5),
        PillButton(onPressed: onDone, child: const Text('Done')),
      ],
    ),
  );
}
