import 'dart:io';

import 'package:find_my_patterns/core/audio/diary_audio_recorder.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/guiding_question.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/theme/journal_metrics.dart';
import 'package:find_my_patterns/features/compose/first_pattern_card.dart';
import 'package:find_my_patterns/features/compose/guided_question_flow.dart';
import 'package:find_my_patterns/features/compose/insight_progress_panel.dart';
import 'package:find_my_patterns/features/compose/voice_answer_recorder.dart';
import 'package:flutter/material.dart';

import '../../core/audio/fake_audio_recorder_plugin.dart';
import '../../features/compose/json_fixtures.dart';
import '../harness.dart';
import '../screen_registry.dart';

/// Wraps [child] the way `entry_composer_screen.dart` actually does: a
/// `Padding(EdgeInsets.all(JournalSpacing.x5))` around a
/// `CrossAxisAlignment.stretch` `Column`, both sides eating into the
/// screen's own 320/360dp width before any of these widgets see it.
/// Handing a bare `Scaffold(body: ...)` the full screen width would be
/// exactly the trap `ACCESSIBILITY.md` §6 warns about (#163): a harness more
/// generous than the real screen, measuring nothing.
Widget _composerBody(Widget child) => MaterialApp(
  theme: buildLightTheme(),
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(JournalSpacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [child],
      ),
    ),
  ),
);

/// A recorder over the fake plugin (never a real platform channel) writing
/// into a real-but-untouched temp directory, the same seam
/// `guided_question_flow_test.dart` and `entry_composer_screen_test.dart`
/// already use.
DiaryAudioRecorder _fakeRecorder() => DiaryAudioRecorder(
  plugin: FakeAudioRecorderPlugin(),
  cacheDirectory: () async => Directory.systemTemp,
);

/// The diary's first surfaced pattern (L-3/#38) -- only [FirstPatternCard]'s
/// own fixed copy is shown, no field of this read directly, so its exact
/// content does not matter beyond satisfying the constructor.
final _firstPattern = patternFromJson(
  patternJson(occurrenceCount: 12),
  FeelingCatalog.empty,
);

/// Two-digit counts on `topicsTracked`/`confirmedEntries` -- both grow
/// unboundedly with the diary's own size, so a real diary can easily reach
/// them, unlike the single-digit "work"/"anxious" example the unit tests
/// use. `occurrences` and `threshold` are *not* free to invent a larger
/// pair from, though: `ProgressPairOut.threshold` is always
/// `MIN_OCCURRENCE_THRESHOLD` (`backend/src/insights/constants.ts`) echoed
/// verbatim, currently a fixed `3`, and a pair only appears here at all
/// while `occurrences < threshold` -- past that it is a surfaced pattern,
/// not near-threshold progress. `2 of 3` is not just realistic, it is the
/// module doc comment's own canonical example. `topic` is the longest
/// canonical name `backend/src/topics/canonicalization.ts`'s
/// `CURATED_TOPIC_KEYWORDS` can actually emit (topics are otherwise
/// free-text, but this keeps the case to a name the source is guaranteed
/// to produce); `feeling` is a real key from `feeling-vocabulary.ts`.
const _insightProgress = InsightProgress(
  16,
  42,
  [ProgressPair('fruit and vegetables', 'overwhelmed', 2, 3)],
  0,
  3,
);

/// The guiding-question library's three mandatory prompts (`general_feeling`,
/// `mind_body`, `small_influences`), verbatim from
/// `backend/src/db/seed.ts`'s `GUIDING_QUESTIONS` -- the longest wording a
/// real diary shows, not a placeholder.
const _generalQuestion = GuidingQuestion(
  'general_feeling',
  QuestionCategory.general,
  'What happened since your last entry — and who was around?',
  [],
  true,
);
const _mindBodyQuestion = GuidingQuestion(
  'mind_body',
  QuestionCategory.mindBody,
  'What did you notice in your mind and body?',
  [],
  true,
);
const _smallInfluencesQuestion = GuidingQuestion(
  'small_influences',
  QuestionCategory.smallInfluences,
  'Anything small that might have influenced you? (sleep, food, movement…)',
  [],
  true,
);

/// The one optional prompt `matchingOptionalQuestions` can actually surface
/// (the three time-of-day prompts in the same seed carry no trigger
/// keywords at all, so they never enter through this mechanism) -- with the
/// real trigger keyword list, verbatim.
const _responseOutcomeQuestion = GuidingQuestion(
  'response_outcome',
  QuestionCategory.responseOutcome,
  'What did you do next, and what changed afterward?',
  [
    'stressed',
    'sad',
    'depressed',
    'anxious',
    'angry',
    'upset',
    'overwhelmed',
    'exhausted',
    'tired',
    'sleepy',
    'pain',
    'headache',
    'argument',
    'conflict',
    'cried',
    'panic',
    'frustrated',
    'difficult',
    'rough',
    'awful',
    'terrible',
    'happy',
    'excited',
    'proud',
    'great',
  ],
  false,
);

const _guidedLibrary = [
  _generalQuestion,
  _mindBodyQuestion,
  _smallInfluencesQuestion,
  _responseOutcomeQuestion,
];

/// Every mandatory question answered, one mentioning "stressed" so
/// `matchingOptionalQuestions` pulls `_responseOutcomeQuestion` in as a
/// fourth step -- the highest step count this library can reach, landing on
/// the last step so both `_StepTrack`'s "Step 4 of 4" row and the
/// Back/"Save entry" row are on screen at once, the two rows #165 measured.
const _guidedAnswers = {
  'general_feeling':
      'It was a stressed kind of day, work bled into the evening.',
  'mind_body':
      'Tense shoulders, a tight jaw, restless legs by the time I sat down.',
  'small_influences':
      'Barely slept, skipped lunch, went for a short walk after dinner.',
  'response_outcome':
      'Took a long shower and journaled before bed, which helped some.',
};

/// `lib/features/compose/ and lib/features/entry/`.
final composeEntry = ScreenArea(
  name: 'compose entry',
  cases: [
    ScreenCase(
      name: 'FirstPatternCard',
      source: 'features/compose/first_pattern_card.dart',
      build: () => _composerBody(
        FirstPatternCard(pattern: _firstPattern, onTap: () {}),
      ),
    ),
    ScreenCase(
      name: 'InsightProgressPanel',
      source: 'features/compose/insight_progress_panel.dart',
      build: () =>
          _composerBody(const InsightProgressPanel(progress: _insightProgress)),
    ),
    ScreenCase(
      name: 'GuidedQuestionFlow',
      source: 'features/compose/guided_question_flow.dart',
      // `GuidedQuestionFlow` embeds `VoiceAnswerRecorder`, a
      // `ConsumerStatefulWidget` -- needs a `ProviderScope` ancestor, hence
      // `Harness().scope` rather than a bare `MaterialApp`.
      build: () => Harness().scope(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(JournalSpacing.x5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // `Expanded`, matching `entry_composer_screen.dart`'s own
                  // wrapping -- `GuidedQuestionFlow`'s build has its own
                  // `Expanded` child, which needs a bounded height from its
                  // ancestor the same way the real screen provides one.
                  Expanded(
                    child: GuidedQuestionFlow(
                      library: _guidedLibrary,
                      answers: _guidedAnswers,
                      stepIndex: 3,
                      onAnswerChange: (_, _) {},
                      onStepChange: (_) {},
                      onBypassToFreeform: () {},
                      onComplete: (_) {},
                      recorder: _fakeRecorder(),
                      transcriptionDelay: (_) async {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    ScreenCase(
      name: 'VoiceAnswerRecorder',
      source: 'features/compose/voice_answer_recorder.dart',
      // Standalone, at its default idle state ("Speak instead") -- the
      // state every composer stage mounts it in, and the one #165 measured.
      // `_RecorderPhase.recording`/`.transcribing` are private state this
      // widget owns itself, unreachable from a one-shot `build()` closure
      // without a tap the sweep never performs.
      build: () => Harness().scope(
        _composerBody(
          VoiceAnswerRecorder(
            onTranscript: (_) {},
            recorder: _fakeRecorder(),
            transcriptionDelay: (_) async {},
          ),
        ),
      ),
    ),
  ],
  unswept: const {},
);
