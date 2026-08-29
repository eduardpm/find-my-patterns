import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/diary/diary_providers.dart';
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

  group('suggestion polling', () {
    test(
      'does not poll when the saved entry is not analysisPending',
      () async {
        final env = await readyController([
          ...bootReplies(),
          FakeReply(201, body: entryJson()), // analysisPending defaults false
        ]);

        await env.controller.saveFreeform('A long day.');
        await env.controller.suggestionPollSettled;

        expect(
          env.container.read(entryComposerControllerProvider).isPollingSuggestions,
          isFalse,
        );
        // Nothing beyond the boot calls and the create itself: no GET
        // /entries/{id} was ever issued.
        expect(env.adapter.requests, hasLength(4));
      },
    );

    test(
      'polls GET /entries/{id} until a suggestion arrives, then pre-fills it',
      () async {
        final env = await readyController([
          ...bootReplies(),
          FakeReply(201, body: entryJson(analysisPending: true)),
          FakeReply(200, body: entryJson(analysisPending: true)), // still working
          FakeReply(
            200,
            body: entryJson(
              analysisPending: false,
              suggestedFeelings: [suggestedFeelingJson(key: 'happy')],
            ),
          ),
        ]);
        env.controller.pollDelay = (_) async {};

        await env.controller.saveFreeform('A long day.');
        expect(
          env.container.read(entryComposerControllerProvider).isPollingSuggestions,
          isTrue,
        );

        await env.controller.suggestionPollSettled;

        final state = env.container.read(entryComposerControllerProvider);
        expect(state.isPollingSuggestions, isFalse);
        final entry = (state.stage as ConfirmFeelingStage).entry;
        expect(entry.suggestedFeelings, hasLength(1));
        expect(entry.suggestedFeelings.single.feeling.key, 'happy');
      },
    );

    test(
      'gives up after enough attempts and degrades to manual picking, '
      'without setting an error',
      () async {
        final env = await readyController([
          ...bootReplies(),
          FakeReply(201, body: entryJson(analysisPending: true)),
          // 12 more "still working" polls -- one per attempt in
          // EntryComposerController's poll loop -- and never a settled one.
          for (var i = 0; i < 12; i++)
            FakeReply(200, body: entryJson(analysisPending: true)),
        ]);
        env.controller.pollDelay = (_) async {};

        await env.controller.saveFreeform('A long day.');
        await env.controller.suggestionPollSettled;

        final state = env.container.read(entryComposerControllerProvider);
        expect(state.isPollingSuggestions, isFalse);
        expect(state.errorMessage, isNull);
        final entry = (state.stage as ConfirmFeelingStage).entry;
        expect(entry.suggestedFeelings, isEmpty);
      },
    );

    test(
      'a transient poll failure is retried rather than surfaced as an error',
      () async {
        final env = await readyController([
          ...bootReplies(),
          FakeReply(201, body: entryJson(analysisPending: true)),
          FakeReply(500, body: {'error': 'boom'}),
          FakeReply(
            200,
            body: entryJson(
              analysisPending: false,
              suggestedFeelings: [suggestedFeelingJson(key: 'sad')],
            ),
          ),
        ]);
        env.controller.pollDelay = (_) async {};

        await env.controller.saveFreeform('A long day.');
        await env.controller.suggestionPollSettled;

        final state = env.container.read(entryComposerControllerProvider);
        expect(state.errorMessage, isNull);
        expect(state.isPollingSuggestions, isFalse);
        final entry = (state.stage as ConfirmFeelingStage).entry;
        expect(entry.suggestedFeelings.single.feeling.key, 'sad');
      },
    );
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

    test(
      'bumps diaryWriteSignalProvider once the entry is stored, whether or '
      'not an echo follows -- Today refreshes either way it exits',
      () async {
        final env = await readyController([
          ...bootReplies(),
          FakeReply(200, body: entryJson()),
          FakeReply(200, body: echoJson(count: 0)),
        ]);
        expect(env.container.read(diaryWriteSignalProvider), 0);

        await env.controller.confirmFeelings(
          entryId: 'entry-1',
          version: 1,
          feelings: const [],
          intensities: const {},
        );

        expect(env.container.read(diaryWriteSignalProvider), 1);
      },
    );

    test(
      'a confirm failure never bumps diaryWriteSignalProvider -- nothing '
      'was actually stored',
      () async {
        final env = await readyController([
          ...bootReplies(),
          FakeReply(500, body: {'error': 'confirm failed'}),
        ]);

        await env.controller.confirmFeelings(
          entryId: 'entry-1',
          version: 1,
          feelings: const [],
          intensities: const {},
        );

        expect(env.container.read(diaryWriteSignalProvider), 0);
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
