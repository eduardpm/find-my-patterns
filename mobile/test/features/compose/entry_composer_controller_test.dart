import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/diary/guiding_question.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/compose/entry_composer_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

void main() {
  ProviderContainer buildContainer(FakeHttpAdapter adapter) {
    final harness = Harness(
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
      adapter: adapter,
    );
    final container = ProviderContainer(
      overrides: [
        requireAuthProvider.overrideWithValue(harness.requireAuth),
        settingsStoreProvider.overrideWithValue(harness.store),
        apiClientProvider.overrideWithValue(harness.client),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// The three background loads `build()` fires, in the order they hit the
  /// network: feelings first (so it primes the shared `FeelingsApi` cache),
  /// then guiding questions, then insights (whose own feelings lookup then
  /// costs nothing).
  List<FakeReply> bootReplies({
    FakeReply? feelings,
    FakeReply? guiding,
    FakeReply? insights,
  }) => [
    feelings ?? FakeReply(200, body: feelingsCatalogJson()),
    guiding ?? FakeReply(200, body: guidingQuestionsJson()),
    insights ?? FakeReply(200, body: insightsJson()),
  ];

  /// Builds a container from [replies] and waits for the controller's
  /// initial background load to finish before handing back both.
  Future<
    ({
      ProviderContainer container,
      EntryComposerController controller,
      FakeHttpAdapter adapter,
    })
  >
  readyController(List<FakeReply> replies) async {
    final adapter = FakeHttpAdapter(replies);
    final container = buildContainer(adapter);
    final controller = container.read(entryComposerControllerProvider.notifier);
    await controller.ready;
    return (container: container, controller: controller, adapter: adapter);
  }

  group('build', () {
    test('loads the guiding questions, feeling groups and constants', () async {
      final env = await readyController(bootReplies());

      final state = env.container.read(entryComposerControllerProvider);
      expect(state.stage, const GuidedStage());
      expect(state.guidingQuestions, hasLength(2));
      expect(state.feelingGroups, hasLength(2));
      expect(state.constants.recencyWindowDays, 30);
    });

    test(
      'falls back to freeform when the guiding-question library fails',
      () async {
        final env = await readyController(
          bootReplies(guiding: FakeReply(500, body: {'error': 'boom'})),
        );

        final state = env.container.read(entryComposerControllerProvider);
        expect(state.stage, const FreeformStage());
        expect(state.errorMessage, isNotNull);
      },
    );

    test(
      'a failed feeling-groups fetch is silent -- saving still works',
      () async {
        final env = await readyController([
          FakeReply(500, body: {'error': 'boom'}), // feelings
          FakeReply(200, body: guidingQuestionsJson()), // guiding
          FakeReply(
            500,
            body: {'error': 'boom'},
          ), // insights' own retry of feelings
        ]);

        final state = env.container.read(entryComposerControllerProvider);
        expect(state.stage, const GuidedStage());
        expect(state.errorMessage, isNull);
        expect(state.feelingGroups, isEmpty);
        expect(state.constants.recencyWindowDays, 30); // still the placeholder
      },
    );
  });

  group('switchToFreeform', () {
    test(
      'seeds the freeform draft from the guided answers, blank-line joined',
      () async {
        final env = await readyController(bootReplies());
        env.controller.updateGuidedAnswer('general', 'Feeling okay.');
        env.controller.updateGuidedAnswer('work', 'Busy day.');

        env.controller.switchToFreeform();

        final state = env.container.read(entryComposerControllerProvider);
        expect(state.stage, const FreeformStage());
        expect(state.freeformText, 'Feeling okay.\n\nBusy day.');
        // The guided answers are left intact so switching back is lossless.
        expect(state.guidedAnswers['general'], 'Feeling okay.');
      },
    );

    test('leaves an already-started freeform draft alone', () async {
      final env = await readyController(bootReplies());
      env.controller.updateGuidedAnswer('general', 'Feeling okay.');
      env.controller.updateFreeformText('Already writing this.');

      env.controller.switchToFreeform();

      expect(
        env.container.read(entryComposerControllerProvider).freeformText,
        'Already writing this.',
      );
    });

    test('switching back to guided keeps the step and answers', () async {
      final env = await readyController(bootReplies());
      env.controller.updateGuidedAnswer('general', 'Feeling okay.');
      env.controller.updateGuidedStep(1);
      env.controller.switchToFreeform();

      env.controller.switchToGuided();

      final state = env.container.read(entryComposerControllerProvider);
      expect(state.stage, const GuidedStage());
      expect(state.guidedStepIndex, 1);
      expect(state.guidedAnswers['general'], 'Feeling okay.');
    });
  });

  group('saveGuided', () {
    test('does nothing for an empty answer list', () async {
      final env = await readyController(bootReplies());

      await env.controller.saveGuided(const []);

      expect(
        env.container.read(entryComposerControllerProvider).stage,
        const GuidedStage(),
      );
    });

    test('moves to ConfirmFeelingStage on success', () async {
      final env = await readyController([
        ...bootReplies(),
        FakeReply(201, body: entryJson()),
      ]);

      await env.controller.saveGuided(const [
        GuidingQuestionAnswer('general', 'Okay.'),
      ]);

      final state = env.container.read(entryComposerControllerProvider);
      expect(state.stage, isA<ConfirmFeelingStage>());
      expect((state.stage as ConfirmFeelingStage).entry.id, 'entry-1');
      expect(state.isSaving, isFalse);
    });

    test('records the error message on failure', () async {
      final env = await readyController([
        ...bootReplies(),
        FakeReply(500, body: {'error': 'server exploded'}),
      ]);

      await env.controller.saveGuided(const [
        GuidingQuestionAnswer('general', 'Okay.'),
      ]);

      final state = env.container.read(entryComposerControllerProvider);
      expect(state.stage, const GuidedStage());
      expect(state.errorMessage, 'server exploded');
      expect(state.isSaving, isFalse);
    });
  });

  group('saveFreeform', () {
    test('does nothing for blank text', () async {
      final env = await readyController(bootReplies());

      await env.controller.saveFreeform('   ');

      expect(
        env.container.read(entryComposerControllerProvider).stage,
        const GuidedStage(),
      );
    });

    test('trims the text and moves to ConfirmFeelingStage', () async {
      final env = await readyController([
        ...bootReplies(),
        FakeReply(201, body: entryJson()),
      ]);

      await env.controller.saveFreeform('  hello world  ');

      expect(env.adapter.requests.last.data, {
        'mode': 'freeform',
        'raw_text': 'hello world',
      });
      expect(
        env.container.read(entryComposerControllerProvider).stage,
        isA<ConfirmFeelingStage>(),
      );
    });
  });

  group('confirmFeelings', () {
    test(
      'returns true and stays off EchoStage when there is nothing to echo',
      () async {
        final env = await readyController([
          ...bootReplies(),
          FakeReply(200, body: entryJson()),
          FakeReply(200, body: echoJson(count: 0)),
        ]);

        final done = await env.controller.confirmFeelings(
          entryId: 'entry-1',
          version: 1,
          feelings: const [],
          intensities: const {},
        );

        expect(done, isTrue);
        expect(
          env.container.read(entryComposerControllerProvider).stage,
          isNot(isA<EchoStage>()),
        );
      },
    );

    test(
      'moves to EchoStage and returns false when the diary has echoes',
      () async {
        final env = await readyController([
          ...bootReplies(),
          FakeReply(200, body: entryJson()),
          FakeReply(200, body: echoJson(count: 2)),
        ]);

        final done = await env.controller.confirmFeelings(
          entryId: 'entry-1',
          version: 1,
          feelings: const [],
          intensities: const {},
        );

        expect(done, isFalse);
        final stage = env.container.read(entryComposerControllerProvider).stage;
        expect(stage, isA<EchoStage>());
        expect((stage as EchoStage).echoes, hasLength(2));
      },
    );

    test(
      'a failed echo fetch is not worth interrupting a finished entry -- '
      'returns true',
      () async {
        final env = await readyController([
          ...bootReplies(),
          FakeReply(200, body: entryJson()),
          FakeReply(500, body: {'error': 'boom'}),
        ]);

        final done = await env.controller.confirmFeelings(
          entryId: 'entry-1',
          version: 1,
          feelings: const [],
          intensities: const {},
        );

        expect(done, isTrue);
      },
    );

    test(
      'records the error message and returns false on a confirm failure',
      () async {
        final env = await readyController([
          ...bootReplies(),
          FakeReply(500, body: {'error': 'confirm failed'}),
        ]);

        final done = await env.controller.confirmFeelings(
          entryId: 'entry-1',
          version: 1,
          feelings: const [],
          intensities: const {},
        );

        expect(done, isFalse);
        final state = env.container.read(entryComposerControllerProvider);
        expect(state.errorMessage, 'confirm failed');
        expect(state.isSaving, isFalse);
      },
    );
  });

  group('dismissError', () {
    test('clears the error message', () async {
      final env = await readyController(
        bootReplies(guiding: FakeReply(500, body: {'error': 'boom'})),
      );
      expect(
        env.container.read(entryComposerControllerProvider).errorMessage,
        isNotNull,
      );

      env.controller.dismissError();

      expect(
        env.container.read(entryComposerControllerProvider).errorMessage,
        isNull,
      );
    });
  });
}
