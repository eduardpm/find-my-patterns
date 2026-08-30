import 'package:flutter/material.dart';

import '../../core/audio/diary_audio_recorder.dart';
import '../../core/diary/guiding_question.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/theme/journal_typography.dart';
import '../../core/widgets/journal.dart';
import 'voice_answer_recorder.dart';

/// Sequential guided-question entry flow.
///
/// Always shows the single mandatory prompt first, then 0–2 optional
/// prompts chosen client-side by [matchingOptionalQuestions] as the user
/// types, with zero network calls mid-entry.
///
/// **Answers and the current step are owned by the caller**, not by this
/// widget — they used to live here, which meant a trip through freeform and
/// back discarded every answer and dropped the person at step 1. This is a
/// controlled component: [answers] and [stepIndex] work the same way a
/// [TextField]'s `controller` does, and this widget only ever proposes a
/// next value through [onAnswerChange]/[onStepChange].
///
/// Every step's answer field autofocuses (#14) — including the first, so
/// the composer opens with the keyboard already up — because each step is a
/// freshly-keyed [_QuestionStep] rather than one field being re-purposed,
/// so `autofocus: true` fires again on every `Next`/`Skip`/`Back`.
///
/// Every step also carries a "Skip" action (#14): unlike `Next`/`Save
/// entry`, it is never gated on the current field being answered — it
/// explicitly clears whatever is in it and moves on, so "skipped" and
/// "answered blank" are the same on-wire state. The one thing it refuses is
/// leaving the whole flow with nothing to save: skipping the last question
/// is disabled exactly when every other one is blank too, the same
/// condition that disables `Save entry` and shows the "Write at least one
/// answer." hint.
class GuidedQuestionFlow extends StatefulWidget {
  /// Builds the guided flow over [library], reading answers from [answers]
  /// and the current position from [stepIndex].
  const GuidedQuestionFlow({
    super.key,
    required this.library,
    required this.answers,
    required this.stepIndex,
    required this.onAnswerChange,
    required this.onStepChange,
    required this.onBypassToFreeform,
    required this.onComplete,
    this.recorder,
    this.transcriptionDelay = Future.delayed,
  });

  /// The guiding-question library, mandatory prompt(s) first by convention.
  final List<GuidingQuestion> library;

  /// Every answer typed so far, keyed by [GuidingQuestion.key].
  final Map<String, String> answers;

  /// The step currently on screen. Not trusted as-is: the optional list can
  /// shrink as well as grow, so this is clamped to the live step count on
  /// every build rather than assumed valid.
  final int stepIndex;

  /// Called with a question's key and its new answer text on every
  /// keystroke.
  final void Function(String questionKey, String text) onAnswerChange;

  /// Called with the step to move to, for both "Back" and "Next".
  final ValueChanged<int> onStepChange;

  /// Called when "Write freely instead" is tapped.
  final VoidCallback onBypassToFreeform;

  /// Called with the answered questions (blank ones dropped, every answer
  /// trimmed) when "Save entry" is tapped on the last step.
  final ValueChanged<List<GuidingQuestionAnswer>> onComplete;

  /// The recorder each step's voice button uses. Defaults to the real
  /// device microphone; a test injects one built over a fake plugin.
  final DiaryAudioRecorder? recorder;

  /// Injected into the voice recorder's transcription poll loop, so a test
  /// never waits on a real clock.
  final Future<void> Function(Duration) transcriptionDelay;

  @override
  State<GuidedQuestionFlow> createState() => _GuidedQuestionFlowState();
}

class _GuidedQuestionFlowState extends State<GuidedQuestionFlow> {
  /// Whether a voice recording is in progress or being transcribed on the
  /// step currently showing. Purely local: unlike the answers themselves,
  /// nothing about a switch to freeform and back needs to remember that a
  /// step's mic button was mid-recording.
  bool _voiceBusy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mandatoryQuestions = [
      for (final question in widget.library)
        if (question.isMandatory) question,
    ];
    final mandatoryText = mandatoryQuestions
        .map((question) => widget.answers[question.key] ?? '')
        .join(' ');
    final optionalQuestions = matchingOptionalQuestions(
      mandatoryText,
      widget.library,
    );
    final questions = [...mandatoryQuestions, ...optionalQuestions];
    final totalSteps = questions.isEmpty ? 1 : questions.length;
    // The list can shrink as well as grow -- deleting a trigger word
    // removes its optional prompt -- so the step from the caller is
    // clamped rather than trusted.
    final currentStep = widget.stepIndex.clamp(0, totalSteps - 1);
    final question = currentStep < questions.length
        ? questions[currentStep]
        : null;
    final answerKey = question?.key ?? 'fallback';
    final answerText = widget.answers[answerKey] ?? '';
    final isLastStep = currentStep == totalSteps - 1;

    // Whether *some* question in the flow -- not necessarily the one on
    // screen -- has a non-blank answer. Drives `Save entry` on the last
    // step (#14): a blank current field no longer disqualifies it on its
    // own, since Skip exists precisely to leave one blank.
    final hasAnyAnswer = questions.any(
      (q) => (widget.answers[q.key] ?? '').trim().isNotEmpty,
    );
    // The same, excluding the question on screen -- what would be left if
    // Skip discarded it right now.
    final hasOtherAnswer = questions.any(
      (q) =>
          q.key != answerKey && (widget.answers[q.key] ?? '').trim().isNotEmpty,
    );

    final canAdvance =
        !_voiceBusy &&
        (isLastStep
            ? hasAnyAnswer
            : (question == null ||
                  !question.isMandatory ||
                  answerText.trim().isNotEmpty));

    // Skip is never blocked by mandatory-ness (#14) -- only by a recording
    // in progress, and by the same floor `Save entry` is held to: skipping
    // the last question must never be the tap that empties the whole flow.
    final canSkip =
        question != null && !_voiceBusy && (!isLastStep || hasOtherAnswer);

    void finishOrAdvance(Map<String, String> answersForSubmit) {
      if (isLastStep) {
        widget.onComplete([
          for (final q in questions)
            if ((answersForSubmit[q.key] ?? '').trim().isNotEmpty)
              GuidingQuestionAnswer(q.key, answersForSubmit[q.key]!.trim()),
        ]);
      } else {
        widget.onStepChange(currentStep + 1);
      }
    }

    // Explicitly clears this question's answer before advancing/finishing,
    // rather than trusting the next build to see it cleared -- `onComplete`
    // reads its list from the map handed to [finishOrAdvance] right here,
    // not from [widget.answers] after a rebuild that has not happened yet.
    void skip() {
      widget.onAnswerChange(answerKey, '');
      finishOrAdvance({...widget.answers, answerKey: ''});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepTrack(current: currentStep, total: totalSteps),
        const SizedBox(height: JournalSpacing.x5),
        Expanded(
          child: _QuestionStep(
            key: ValueKey(answerKey),
            prompt: question?.promptText ?? "What's been happening?",
            value: answerText,
            onValueChange: (text) => widget.onAnswerChange(answerKey, text),
            onVoiceBusyChange: (busy) => setState(() => _voiceBusy = busy),
            recorder: widget.recorder,
            transcriptionDelay: widget.transcriptionDelay,
          ),
        ),
        if (question != null) ...[
          const SizedBox(height: JournalSpacing.x1),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: canSkip ? skip : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
              ),
              child: const Text('Skip'),
            ),
          ),
        ],
        if (isLastStep && !hasAnyAnswer) ...[
          Text(
            'Write at least one answer.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: JournalSpacing.x2),
        ],
        const SizedBox(height: JournalSpacing.x4),
        // The two actions are not peers: one advances the flow, the other
        // abandons it. Separated rather than sat side by side, so "write
        // freely" is never the button the hand goes to by momentum.
        SecondaryPillButton(
          onPressed: widget.onBypassToFreeform,
          child: const Text('Write freely instead'),
        ),
        const SizedBox(height: JournalSpacing.x3),
        // `Wrap`, not `Row` (#165) -- two fixed-size pill buttons that do
        // not both fit one line at 320dp/2x ("Back" + "Save entry" needed
        // 152-176px more than the row had). Each pill keeps its full label
        // rather than shrinking or truncating; when they don't share a
        // line, "Save entry"/"Next" drops to its own line below "Back"
        // instead of overflowing it.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: JournalSpacing.x2,
          children: [
            if (currentStep > 0)
              SecondaryPillButton(
                onPressed: () => widget.onStepChange(currentStep - 1),
                child: const Text('Back'),
              )
            else
              const SizedBox(width: 1),
            PillButton(
              onPressed: canAdvance
                  ? () => finishOrAdvance(widget.answers)
                  : null,
              child: Text(isLastStep ? 'Save entry' : 'Next'),
            ),
          ],
        ),
      ],
    );
  }
}

/// One question's prompt, text field and voice recorder.
///
/// A [StatefulWidget] holding its own [TextEditingController], rather than
/// a stateless field fed `initialValue`: [TextFormField] only honours
/// `initialValue` on its very first build, so a plain stateless field would
/// silently ignore the text a voice transcript appends after the field has
/// already mounted. The controller is instead kept in sync with [value] on
/// every rebuild, so an external change — the voice recorder's appended
/// transcript — actually lands in what is on screen.
class _QuestionStep extends StatefulWidget {
  const _QuestionStep({
    super.key,
    required this.prompt,
    required this.value,
    required this.onValueChange,
    required this.onVoiceBusyChange,
    required this.recorder,
    required this.transcriptionDelay,
  });

  final String prompt;
  final String value;
  final ValueChanged<String> onValueChange;
  final ValueChanged<bool> onVoiceBusyChange;
  final DiaryAudioRecorder? recorder;
  final Future<void> Function(Duration) transcriptionDelay;

  @override
  State<_QuestionStep> createState() => _QuestionStepState();
}

class _QuestionStepState extends State<_QuestionStep> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant _QuestionStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.prompt, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: JournalSpacing.x5),
        TextFormField(
          controller: _controller,
          // This whole widget is freshly built (a new key, a new state) on
          // every step change (#14) -- see this file's class-level doc
          // comment -- which is what makes `autofocus: true` fire again on
          // every `Next`/`Skip`/`Back` instead of only on the very first
          // step.
          autofocus: true,
          onChanged: widget.onValueChange,
          minLines: 4,
          maxLines: null,
          style: JournalType.prose,
          decoration: const InputDecoration(
            hintText: 'Type your answer…',
            border: OutlineInputBorder(borderRadius: JournalShapes.medium),
          ),
        ),
        const SizedBox(height: JournalSpacing.x3),
        VoiceAnswerRecorder(
          // Appended, not replaced: someone who types half an answer and
          // dictates the rest should end up with both halves.
          onTranscript: (transcript) {
            final existing = widget.value.trim();
            widget.onValueChange(
              existing.isEmpty ? transcript : '$existing $transcript',
            );
          },
          onBusyChange: widget.onVoiceBusyChange,
          recorder: widget.recorder,
          transcriptionDelay: widget.transcriptionDelay,
        ),
      ],
    ),
  );
}

/// The step track.
///
/// Drawn as discrete segments rather than a continuous bar, because the
/// prompt list grows while the user answers — a mention of "work" pulls in
/// the work prompt. A continuous bar would appear to move *backwards* when
/// the denominator rose, which is a lie about progress; adding a segment is
/// not.
class _StepTrack extends StatelessWidget {
  const _StepTrack({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `Wrap`, not `Row` (#165) -- "Guided" and "Step N of M" no longer
        // share one line once the step count and the text scale both grow
        // (measured 152-167px short of the row's own width at 320dp/2x).
        // Neither label is truncated or shrunk; "Step N of M" drops to its
        // own line below "Guided" instead of overflowing it.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: JournalSpacing.x1,
          children: [
            const Eyebrow('Guided'),
            Eyebrow('Step ${current + 1} of $total'),
          ],
        ),
        const SizedBox(height: JournalSpacing.x2),
        Row(
          children: [
            for (var index = 0; index < total; index++) ...[
              if (index > 0) const SizedBox(width: JournalSpacing.x1),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: JournalShapes.full,
                    border: Border.all(
                      color: index <= current
                          ? theme.colorScheme.primary
                          : journal.hairline,
                    ),
                    color: index < current
                        ? theme.colorScheme.primary
                        : index == current
                        ? theme.colorScheme.primary.withValues(alpha: 0.45)
                        : theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
