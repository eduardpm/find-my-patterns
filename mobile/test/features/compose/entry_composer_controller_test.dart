import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/diary/diary_providers.dart';
import 'package:find_my_patterns/core/diary/guiding_question.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/compose/composer_draft.dart';
import 'package:find_my_patterns/features/compose/entry_composer_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_composer_draft_store.dart';
import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

void main() {
  ({ProviderContainer container, FakeComposerDraftStore draftStore})
  buildContainer(FakeHttpAdapter adapter, {ComposerDraft? initialDraft}) {
    final harness = Harness(
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
      adapter: adapter,
      initialDraft: initialDraft,
    );
    final container = ProviderContainer(
      overrides: [
        requireAuthProvider.overrideWithValue(harness.requireAuth),
        settingsStoreProvider.overrideWithValue(harness.store),
        apiClientProvider.overrideWithValue(harness.client),
        composerDraftStoreProvider.overrideWithValue(harness.draftStore),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, draftStore: harness.draftStore);
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
  ///
  /// [initialDraft] seeds the fake draft store the way a previous run of
  /// the app having already saved one would. [EntryComposerController
  /// .draftSaveDebounce] defaults to [Duration.zero] here -- there is no
  /// `FakeAsync` clock in a plain `test()` body to fast-forward, so a zero
  /// debounce is what keeps `await controller.draftSaveSettled` resolving
  /// on the next event-loop turn instead of a real wait, per Article 3's
  /// "no real clock". A test asserting on the debounce actually delaying
  /// something overrides [draftSaveDebounce] after this returns.
  Future<
    ({
      ProviderContainer container,
      EntryComposerController controller,
      FakeHttpAdapter adapter,
      FakeComposerDraftStore draftStore,
    })
  >
  readyController(
    List<FakeReply> replies, {
    ComposerDraft? initialDraft,
    Duration draftSaveDebounce = Duration.zero,
  }) async {
    final adapter = FakeHttpAdapter(replies);
    final built = buildContainer(adapter, initialDraft: initialDraft);
    final controller = built.container.read(
      entryComposerControllerProvider.notifier,
    );
    controller.draftSaveDebounce = draftSaveDebounce;
    await controller.ready;
    return (
      container: built.container,
      controller: controller,
      adapter: adapter,
      draftStore: built.draftStore,
    );
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
          env.container
              .read(entryComposerControllerProvider)
              .isPollingSuggestions,
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
          FakeReply(
            200,
            body: entryJson(analysisPending: true),
          ), // still working
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
          env.container
              .read(entryComposerControllerProvider)
              .isPollingSuggestions,
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

  group('hasUnsavedComposition', () {
    test('is false for a freshly booted composer with nothing typed', () async {
      final env = await readyController(bootReplies());

      expect(
        env.container
            .read(entryComposerControllerProvider)
            .hasUnsavedComposition,
        isFalse,
      );
    });

    test('is true once a guided answer has text', () async {
      final env = await readyController(bootReplies());

      env.controller.updateGuidedAnswer('general', 'Feeling okay.');

      expect(
        env.container
            .read(entryComposerControllerProvider)
            .hasUnsavedComposition,
        isTrue,
      );
    });

    test('is true once freeform text is typed', () async {
      final env = await readyController(bootReplies());

      env.controller.switchToFreeform();
      env.controller.updateFreeformText('A long day.');

      expect(
        env.container
            .read(entryComposerControllerProvider)
            .hasUnsavedComposition,
        isTrue,
      );
    });

    test(
      'is true once a later guided step is reached, even if that step\'s '
      'own field is blank',
      () async {
        final env = await readyController(bootReplies());

        env.controller.updateGuidedAnswer('general', 'Feeling okay.');
        env.controller.updateGuidedStep(1);

        expect(
          env.container
              .read(entryComposerControllerProvider)
              .hasUnsavedComposition,
          isTrue,
        );
      },
    );

    test(
      'is false on an empty composer even after reaching freeform',
      () async {
        final env = await readyController(bootReplies());

        env.controller.switchToFreeform();

        expect(
          env.container
              .read(entryComposerControllerProvider)
              .hasUnsavedComposition,
          isFalse,
        );
      },
    );

    test(
      'is false once the entry is saved, even though the just-saved text '
      'is still sitting in state -- the feelings step must never warn '
      'about losing text that is already stored (#4 point 3)',
      () async {
        final env = await readyController([
          ...bootReplies(),
          FakeReply(201, body: entryJson()),
        ]);

        env.controller.updateFreeformText('A long day.');
        await env.controller.saveFreeform('A long day.');

        final state = env.container.read(entryComposerControllerProvider);
        expect(state.stage, isA<ConfirmFeelingStage>());
        expect(state.freeformText, 'A long day.');
        expect(state.hasUnsavedComposition, isFalse);
      },
    );
  });

  group('draft restore', () {
    test('an empty store leaves the composer blank, with no notice', () async {
      final env = await readyController(bootReplies());

      final state = env.container.read(entryComposerControllerProvider);
      expect(state.restoredDraftAt, isNull);
      expect(state.stage, const GuidedStage());
      expect(state.guidedAnswers, isEmpty);
      expect(state.freeformText, isEmpty);
    });

    test(
      "restores a guided draft's stage, step, answers and notice time",
      () async {
        final savedAt = DateTime.utc(2026, 8, 28, 23, 32);

        final env = await readyController(
          bootReplies(),
          initialDraft: ComposerDraft(
            mode: ComposerDraftMode.guided,
            guidedStepIndex: 1,
            guidedAnswers: const {'general': 'Feeling okay.'},
            savedAt: savedAt,
          ),
        );

        final state = env.container.read(entryComposerControllerProvider);
        expect(state.stage, const GuidedStage());
        expect(state.guidedStepIndex, 1);
        expect(state.guidedAnswers, {'general': 'Feeling okay.'});
        expect(state.restoredDraftAt, savedAt);
      },
    );

    test('restores a freeform draft', () async {
      final env = await readyController(
        bootReplies(),
        initialDraft: ComposerDraft(
          mode: ComposerDraftMode.freeform,
          freeformText: 'carried over',
          savedAt: DateTime.utc(2026),
        ),
      );

      final state = env.container.read(entryComposerControllerProvider);
      expect(state.stage, const FreeformStage());
      expect(state.freeformText, 'carried over');
      expect(state.restoredDraftAt, isNotNull);
    });

    test('a saved draft with nothing worth restoring is left alone', () async {
      final env = await readyController(
        bootReplies(),
        initialDraft: ComposerDraft(
          mode: ComposerDraftMode.freeform,
          savedAt: DateTime.utc(2026),
        ),
      );

      final state = env.container.read(entryComposerControllerProvider);
      expect(state.restoredDraftAt, isNull);
      expect(state.stage, const GuidedStage());
    });
  });

  group('draft autosave', () {
    test('debounces a write of the current composition', () async {
      final env = await readyController(bootReplies());
      expect(env.draftStore.saved, isEmpty);

      env.controller.updateGuidedAnswer('general', 'Feeling okay.');
      // Nothing yet -- the debounce timer has not fired.
      expect(env.draftStore.saved, isEmpty);

      await env.controller.draftSaveSettled;

      expect(env.draftStore.saved, hasLength(1));
      expect(env.draftStore.saved.single.mode, ComposerDraftMode.guided);
      expect(env.draftStore.saved.single.guidedAnswers, {
        'general': 'Feeling okay.',
      });
    });

    test(
      'a second edit inside the debounce window replaces the pending write '
      'instead of duplicating it',
      () async {
        final env = await readyController(bootReplies());

        env.controller.updateGuidedAnswer('general', 'Feeling');
        env.controller.updateGuidedAnswer('general', 'Feeling okay.');
        await env.controller.draftSaveSettled;

        expect(env.draftStore.saved, hasLength(1));
        expect(
          env.draftStore.saved.single.guidedAnswers['general'],
          'Feeling okay.',
        );
      },
    );

    test(
      'emptying the composition clears rather than saves the draft',
      () async {
        final env = await readyController(bootReplies());
        env.controller.switchToFreeform();
        env.controller.updateFreeformText('something');
        await env.controller.draftSaveSettled;
        expect(await env.draftStore.load(), isNotNull);

        env.controller.updateFreeformText('');
        await env.controller.draftSaveSettled;

        expect(env.draftStore.clearCount, 1);
        expect(await env.draftStore.load(), isNull);
      },
    );

    test(
      'a step transition alone schedules a save of the new position',
      () async {
        final env = await readyController(bootReplies());
        env.controller.updateGuidedAnswer('general', 'Feeling okay.');
        await env.controller.draftSaveSettled;

        env.controller.updateGuidedStep(1);
        await env.controller.draftSaveSettled;

        expect(env.draftStore.saved.last.guidedStepIndex, 1);
      },
    );

    test(
      'a debounced save mid-flight is genuinely cancelled by discardDraft, '
      'not just made harmless by the state it would have read',
      () async {
        final env = await readyController(bootReplies());

        env.controller.updateFreeformText('will be discarded');
        // No `await` happened between the edit above and this call, so the
        // (zero-duration, in this harness) debounce timer has not had a
        // chance to fire yet -- this is exactly the race `discardDraft`'s
        // cancellation exists to win. Note that discarding also resets
        // `ComposerState` to empty first, so even an *uncancelled* timer
        // would read an already-empty composition and harmlessly call
        // `clear()` a second time rather than writing stale content back --
        // asserting `clearCount == 1` (not just that nothing was saved) is
        // what actually distinguishes a real cancellation from that
        // coincidence: a second, uncancelled `clear()` landing later would
        // push the count to 2.
        await env.controller.discardDraft();
        await Future<void>.delayed(Duration.zero);

        expect(env.draftStore.saved, isEmpty);
        expect(env.draftStore.clearCount, 1);
      },
    );
  });

  group('discardDraft', () {
    test(
      'resets guided and freeform fields, and the restored-draft notice',
      () async {
        final env = await readyController(
          bootReplies(),
          initialDraft: ComposerDraft(
            mode: ComposerDraftMode.guided,
            guidedStepIndex: 1,
            guidedAnswers: const {'general': 'Feeling okay.'},
            savedAt: DateTime.utc(2026),
          ),
        );
        expect(
          env.container.read(entryComposerControllerProvider).restoredDraftAt,
          isNotNull,
        );

        await env.controller.discardDraft();

        final state = env.container.read(entryComposerControllerProvider);
        expect(state.guidedAnswers, isEmpty);
        expect(state.guidedStepIndex, 0);
        expect(state.freeformText, isEmpty);
        expect(state.restoredDraftAt, isNull);
      },
    );

    test('clears the persisted draft', () async {
      final env = await readyController(bootReplies());
      env.controller.updateFreeformText('will be discarded');
      await env.controller.draftSaveSettled;
      expect(await env.draftStore.load(), isNotNull);

      await env.controller.discardDraft();

      expect(env.draftStore.clearCount, greaterThanOrEqualTo(1));
      expect(await env.draftStore.load(), isNull);
    });
  });

  group('dismissDraftNotice', () {
    test('hides the notice without touching the restored answers', () async {
      final savedAt = DateTime.utc(2026, 8, 28, 23, 32);
      final env = await readyController(
        bootReplies(),
        initialDraft: ComposerDraft(
          mode: ComposerDraftMode.freeform,
          freeformText: 'carried over',
          savedAt: savedAt,
        ),
      );
      expect(
        env.container.read(entryComposerControllerProvider).restoredDraftAt,
        savedAt,
      );

      env.controller.dismissDraftNotice();

      final state = env.container.read(entryComposerControllerProvider);
      expect(state.restoredDraftAt, isNull);
      expect(state.freeformText, 'carried over');
      expect(state.stage, const FreeformStage());
    });
  });

  group('successful save clears the persisted draft', () {
    test(
      'saveGuided clears both the in-memory notice and the stored draft',
      () async {
        final env = await readyController([
          ...bootReplies(),
          FakeReply(201, body: entryJson()),
        ]);
        env.controller.updateGuidedAnswer('general', 'Okay.');
        await env.controller.draftSaveSettled;
        expect(await env.draftStore.load(), isNotNull);

        await env.controller.saveGuided(const [
          GuidingQuestionAnswer('general', 'Okay.'),
        ]);
        await Future<void>.delayed(Duration.zero);

        expect(
          env.container.read(entryComposerControllerProvider).restoredDraftAt,
          isNull,
        );
        expect(env.draftStore.clearCount, greaterThanOrEqualTo(1));
        expect(await env.draftStore.load(), isNull);
      },
    );

    test(
      'saveFreeform clears both the in-memory notice and the stored draft',
      () async {
        final env = await readyController([
          ...bootReplies(),
          FakeReply(201, body: entryJson()),
        ]);
        env.controller.switchToFreeform();
        env.controller.updateFreeformText('A long day.');
        await env.controller.draftSaveSettled;
        expect(await env.draftStore.load(), isNotNull);

        await env.controller.saveFreeform('A long day.');
        await Future<void>.delayed(Duration.zero);

        expect(
          env.container.read(entryComposerControllerProvider).restoredDraftAt,
          isNull,
        );
        expect(env.draftStore.clearCount, greaterThanOrEqualTo(1));
        expect(await env.draftStore.load(), isNull);
      },
    );
  });
}
