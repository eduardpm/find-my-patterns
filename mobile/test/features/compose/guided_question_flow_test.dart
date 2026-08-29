import 'dart:io';

import 'package:find_my_patterns/core/audio/diary_audio_recorder.dart';
import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/diary/guiding_question.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/compose/guided_question_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/audio/fake_audio_recorder_plugin.dart';
import '../../support/fake_http.dart';
import '../../support/harness.dart';

const general = GuidingQuestion(
  'general',
  QuestionCategory.general,
  "What's on your mind?",
  [],
  true,
);
const work = GuidingQuestion(
  'work',
  QuestionCategory.smallInfluences,
  'How was work?',
  ['work'],
  false,
);
const sleep = GuidingQuestion(
  'sleep',
  QuestionCategory.mindBody,
  'How did you sleep?',
  ['sleep', 'tired'],
  false,
);

/// A controlled-component test harness, mirroring the real composer's
/// ownership of the answers and step index: this widget owns nothing of its
/// own, so a test drives it the way the real controller would.
class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    this.library = const [general],
    this.initialAnswers = const {},
    this.initialStep = 0,
    this.onComplete,
    this.onBypass,
  });

  final List<GuidingQuestion> library;
  final Map<String, String> initialAnswers;
  final int initialStep;
  final ValueChanged<List<GuidingQuestionAnswer>>? onComplete;
  final VoidCallback? onBypass;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late Map<String, String> answers = widget.initialAnswers;
  late int stepIndex = widget.initialStep;

  /// Lets a test change [answers] the way an unrelated part of a real
  /// screen might -- never through [GuidedQuestionFlow.onAnswerChange] --
  /// to prove the widget clamps its step to a shrinking question list.
  void setAnswersExternally(Map<String, String> next) =>
      setState(() => answers = next);

  @override
  Widget build(BuildContext context) {
    final harness = Harness(
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
      adapter: FakeHttpAdapter.always(const FakeReply(200, body: {})),
    );
    return ProviderScope(
      overrides: [
        requireAuthProvider.overrideWithValue(harness.requireAuth),
        settingsStoreProvider.overrideWithValue(harness.store),
        apiClientProvider.overrideWithValue(harness.client),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: GuidedQuestionFlow(
            library: widget.library,
            answers: answers,
            stepIndex: stepIndex,
            onAnswerChange: (key, text) =>
                setState(() => answers = {...answers, key: text}),
            onStepChange: (index) => setState(() => stepIndex = index),
            onBypassToFreeform: widget.onBypass ?? () {},
            onComplete: widget.onComplete ?? (_) {},
            // A fake plugin (and a real-but-untouched temp directory,
            // never actually written to since the fake plugin never
            // touches the filesystem) so a tap on "Speak instead" never
            // reaches a real platform channel.
            recorder: DiaryAudioRecorder(
              plugin: FakeAudioRecorderPlugin(),
              cacheDirectory: () async => Directory.systemTemp,
            ),
            transcriptionDelay: (_) async {},
          ),
        ),
      ),
    );
  }
}

/// The "Step N of M" eyebrow renders its text upper-cased for display but
/// keeps the natural casing in its accessibility label -- see
/// `core/widgets/journal.dart`'s `Eyebrow`. Asserting through the label
/// keeps this test about the step *count*, not about that presentation
/// choice.
void expectStepLabel(WidgetTester tester, String label) {
  final handle = tester.ensureSemantics();
  expect(find.bySemanticsLabel(label), findsOneWidget);
  handle.dispose();
}

/// [GuidingQuestionAnswer] has no value equality, so a list literal can't
/// be compared with `==`; this compares the fields that matter instead.
void expectAnswers(
  List<GuidingQuestionAnswer>? actual,
  List<(String, String)> expected,
) {
  expect(
    actual?.map((a) => (a.questionKey, a.answerText)).toList(),
    expected,
  );
}

void main() {
  group('the mandatory step', () {
    testWidgets('shows the mandatory prompt and "Step 1 of 1" alone', (
      tester,
    ) async {
      await tester.pumpWidget(const _Harness());
      expect(find.text("What's on your mind?"), findsOneWidget);
      expectStepLabel(tester, 'Step 1 of 1');
    });

    testWidgets('Next/Save is disabled until the mandatory question is '
        'answered', (tester) async {
      await tester.pumpWidget(const _Harness());
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save entry'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('Next/Save enables once the mandatory question has an '
        'answer', (tester) async {
      await tester.pumpWidget(
        const _Harness(initialAnswers: {'general': 'Fine.'}),
      );
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save entry'),
      );
      expect(saveButton.onPressed, isNotNull);
    });

    testWidgets('typing into the field reports the answer through '
        'onAnswerChange', (tester) async {
      await tester.pumpWidget(const _Harness());
      await tester.enterText(find.byType(TextFormField), 'Feeling okay');
      expect(find.text('Feeling okay'), findsOneWidget);
    });

    testWidgets('has no Back button on the first step', (tester) async {
      await tester.pumpWidget(const _Harness());
      expect(find.text('Back'), findsNothing);
    });
  });

  group('optional questions', () {
    testWidgets('a trigger word in the mandatory answer adds an optional '
        'step', (tester) async {
      await tester.pumpWidget(
        _Harness(
          library: const [general, work],
          initialAnswers: const {'general': 'Long day at work today.'},
        ),
      );
      expectStepLabel(tester, 'Step 1 of 2');
    });

    testWidgets('no trigger word means only the mandatory step shows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Harness(
          library: const [general, work],
          initialAnswers: const {'general': 'A quiet day.'},
        ),
      );
      expectStepLabel(tester, 'Step 1 of 1');
    });

    testWidgets('at most two optional questions are offered', (
      tester,
    ) async {
      const extra = GuidingQuestion(
        'extra',
        QuestionCategory.responseOutcome,
        'How did it turn out?',
        ['work'],
        false,
      );
      await tester.pumpWidget(
        _Harness(
          library: const [general, work, sleep, extra],
          initialAnswers: const {
            'general': 'Work was tiring, I felt tired and slept badly.',
          },
        ),
      );
      // "work", "sleep" and "extra" all match; only 2 optional slots exist.
      expectStepLabel(tester, 'Step 1 of 3');
    });

    testWidgets('the step clamps down when a trigger word is removed and '
        'the optional step disappears', (tester) async {
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: key,
          library: const [general, work],
          initialAnswers: const {'general': 'Busy at work.'},
          initialStep: 1,
        ),
      );
      expectStepLabel(tester, 'Step 2 of 2');
      expect(find.text('How was work?'), findsOneWidget);

      key.currentState!.setAnswersExternally({'general': 'A quiet day.'});
      await tester.pump();

      expectStepLabel(tester, 'Step 1 of 1');
      expect(find.text("What's on your mind?"), findsOneWidget);
    });
  });

  group('advancing', () {
    testWidgets('Next moves to the next step without completing', (
      tester,
    ) async {
      var completed = false;
      await tester.pumpWidget(
        _Harness(
          library: const [general, work],
          initialAnswers: const {'general': 'Busy at work today.'},
          onComplete: (_) => completed = true,
        ),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Next'));
      await tester.pump();

      expect(find.text('How was work?'), findsOneWidget);
      expect(completed, isFalse);
    });

    testWidgets('Back returns to the previous step', (tester) async {
      await tester.pumpWidget(
        _Harness(
          library: const [general, work],
          initialAnswers: const {'general': 'Busy at work today.'},
          initialStep: 1,
        ),
      );
      await tester.tap(find.text('Back'));
      await tester.pump();

      expect(find.text("What's on your mind?"), findsOneWidget);
    });

    testWidgets('Save entry on the last step submits every non-blank '
        'answer, trimmed', (tester) async {
      List<GuidingQuestionAnswer>? submitted;
      await tester.pumpWidget(
        _Harness(
          library: const [general, work],
          initialAnswers: const {
            'general': '  Busy at work today.  ',
            'work': '  Long meeting.  ',
          },
          initialStep: 1,
          onComplete: (answers) => submitted = answers,
        ),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));

      expectAnswers(submitted, [
        ('general', 'Busy at work today.'),
        ('work', 'Long meeting.'),
      ]);
    });

    testWidgets('a blank optional answer is dropped from the submission', (
      tester,
    ) async {
      List<GuidingQuestionAnswer>? submitted;
      await tester.pumpWidget(
        _Harness(
          library: const [general, work],
          initialAnswers: const {
            'general': 'Busy at work today.',
            'work': '   ',
          },
          initialStep: 1,
          onComplete: (answers) => submitted = answers,
        ),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));

      expectAnswers(submitted, [('general', 'Busy at work today.')]);
    });
  });

  group('write freely instead', () {
    testWidgets('is always visible and calls onBypassToFreeform', (
      tester,
    ) async {
      var bypassed = false;
      await tester.pumpWidget(_Harness(onBypass: () => bypassed = true));
      await tester.tap(find.text('Write freely instead'));
      expect(bypassed, isTrue);
    });
  });

  group('voice busy', () {
    testWidgets('disables Next/Save while a recording is busy', (
      tester,
    ) async {
      await tester.pumpWidget(
        const _Harness(initialAnswers: {'general': 'Fine.'}),
      );
      await tester.tap(find.text('Speak instead'));
      await tester.pump();

      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save entry'),
      );
      expect(saveButton.onPressed, isNull);
    });
  });

  group('empty library', () {
    testWidgets('falls back to a generic prompt with "Step 1 of 1"', (
      tester,
    ) async {
      await tester.pumpWidget(const _Harness(library: []));
      expect(find.text("What's been happening?"), findsOneWidget);
      expectStepLabel(tester, 'Step 1 of 1');
    });
  });
}
