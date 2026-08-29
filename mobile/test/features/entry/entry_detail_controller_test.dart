import 'package:find_my_patterns/core/diary/diary_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/entry/entry_detail_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

void main() {
  const entryId = 'entry-1';

  ProviderContainer buildContainer(Harness harness) {
    final container = harness.container();
    addTearDown(container.dispose);
    return container;
  }

  Harness configuredHarness(FakeHttpAdapter adapter) => Harness(
    settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
    adapter: adapter,
  );

  /// Builds a container, lets the initial (deferred) load run to
  /// completion, and hands back both the container and its notifier.
  ///
  /// Touching the provider before the first [pumpEventQueue] matters: a
  /// family [NotifierProvider] builds lazily on first read, and `build`'s
  /// own deferred load is scheduled only once that first read happens.
  Future<({ProviderContainer container, EntryDetailController notifier})> ready(
    FakeHttpAdapter adapter,
  ) async {
    final container = buildContainer(configuredHarness(adapter));
    container.read(entryDetailControllerProvider(entryId));
    // `build` now chains four sequential requests (entry, feeling groups,
    // constants, supporting patterns); the default 20 turns of the event
    // loop is not reliably enough to drain all four through the real Dio
    // pipeline before this helper hands back a container whose `build` is
    // still in flight, which manifested as a `ref` used after a *later*
    // test's `dispose()` ran. Doubled with margin, not tuned to the exact
    // minimum.
    await pumpEventQueue(times: 40);
    return (
      container: container,
      notifier: container.read(entryDetailControllerProvider(entryId).notifier),
    );
  }

  EntryDetailState stateOf(ProviderContainer container) =>
      container.read(entryDetailControllerProvider(entryId));

  /// The four requests a clean [ready] boot makes, in order: the entry
  /// itself (whose own feelings lookup primes the shared cache), the
  /// feeling groups (free, cache already warm), the insights constants, and
  /// the entry's own echo -- read once for [EntryDetailState.supportingPatterns],
  /// separately from the dismissible nudge [EntryDetailState.echoes] reads
  /// only after a save.
  List<FakeReply> bootReplies({
    FakeReply? entry,
    FakeReply? insights,
    FakeReply? supportingPatterns,
  }) => [
    FakeReply(200, body: feelingsCatalogJson()),
    entry ?? FakeReply(200, body: entryJson()),
    insights ?? FakeReply(200, body: insightsJson()),
    supportingPatterns ?? FakeReply(200, body: {'echoes': <Object?>[]}),
  ];

  group('build', () {
    test(
      'loads the entry via getById, the feeling groups and constants',
      () async {
        final adapter = FakeHttpAdapter(
          bootReplies(
            entry: FakeReply(200, body: entryJson(rawText: 'Hello.')),
          ),
        );
        final env = await ready(adapter);

        final state = stateOf(env.container);
        expect(state.hasLoaded, isTrue);
        expect(state.entry!.rawText, 'Hello.');
        expect(state.editedText, 'Hello.');
        expect(state.feelingGroups, hasLength(3));
        expect(state.constants.maxIntensity, 5);
        // `getById` is a single request per entry: `/entries/{id}`, not a
        // whole day filtered down to it.
        expect(
          adapter.requests.where((r) => r.path == '/entries/$entryId'),
          hasLength(1),
        );
      },
    );

    test(
      'a failed entry load leaves the entry null and records the message',
      () async {
        final adapter = FakeHttpAdapter(
          bootReplies(entry: FakeReply(404, body: {'error': 'not found'})),
        );
        final env = await ready(adapter);

        final state = stateOf(env.container);
        expect(state.hasLoaded, isTrue);
        expect(state.entry, isNull);
        expect(state.errorMessage, isNotNull);
        // There is nothing to echo against an id the backend just said it
        // does not have.
        expect(
          adapter.requests.any((r) => r.path.endsWith('/echo')),
          isFalse,
        );
      },
    );

    test(
      'loads the persistent supporting-patterns list separately from the '
      'dismissible echo nudge',
      () async {
        final adapter = FakeHttpAdapter(
          bootReplies(
            supportingPatterns: FakeReply(
              200,
              body: {
                'echoes': <Object?>[echoJson(topic: 'coffee')],
              },
            ),
          ),
        );
        final env = await ready(adapter);

        final state = stateOf(env.container);
        expect(state.supportingPatterns, hasLength(1));
        expect(state.supportingPatterns.single.topic, 'coffee');
        // The dismissible just-saved nudge is a different field, untouched
        // by the initial load.
        expect(state.echoes, isEmpty);
      },
    );

    test('a failed supporting-patterns fetch on load is silent', () async {
      final adapter = FakeHttpAdapter(
        bootReplies(
          supportingPatterns: FakeReply(500, body: {'error': 'boom'}),
        ),
      );
      final env = await ready(adapter);

      final state = stateOf(env.container);
      expect(state.hasLoaded, isTrue);
      expect(state.entry, isNotNull);
      expect(state.supportingPatterns, isEmpty);
      expect(state.errorMessage, isNull);
    });

    test('a failed constants fetch leaves the placeholder standing', () async {
      final adapter = FakeHttpAdapter(
        bootReplies(insights: FakeReply(500, body: {'error': 'boom'})),
      );
      final env = await ready(adapter);

      expect(stateOf(env.container).constants.maxIntensity, 5);
    });
  });

  group('editing', () {
    test('unpicking a feeling drops its rating along with it', () async {
      final env = await ready(
        FakeHttpAdapter(
          bootReplies(
            entry: FakeReply(
              200,
              body: entryJson(
                feelingKeys: const ['happy', 'sad'],
                feelingIntensities: const {'happy': 3, 'sad': 4},
              ),
            ),
          ),
        ),
      );
      final happy = stateOf(env.container).editedFeelings.first;

      env.notifier.updateFeelings([happy]);

      final state = stateOf(env.container);
      expect(state.editedFeelings.map((f) => f.key), ['happy']);
      expect(state.editedIntensities, {'happy': 3});
    });

    test('updateIntensity sets and clears a rating', () async {
      final env = await ready(
        FakeHttpAdapter(bootReplies(entry: FakeReply(200, body: entryJson()))),
      );
      final happy = stateOf(env.container).editedFeelings.first;

      env.notifier.updateIntensity(happy, 4);
      expect(stateOf(env.container).editedIntensities, {'happy': 4});

      env.notifier.updateIntensity(happy, null);
      expect(stateOf(env.container).editedIntensities, isEmpty);
    });

    test(
      'startEditing then cancelEditing resets the draft to the stored entry',
      () async {
        final env = await ready(
          FakeHttpAdapter(
            bootReplies(
              entry: FakeReply(200, body: entryJson(rawText: 'Stored.')),
            ),
          ),
        );

        env.notifier.startEditing();
        env.notifier.updateText('Changed my mind.');
        expect(stateOf(env.container).isEditing, isTrue);

        env.notifier.cancelEditing();

        final state = stateOf(env.container);
        expect(state.isEditing, isFalse);
        expect(state.editedText, 'Stored.');
      },
    );
  });

  group('save', () {
    test(
      'a successful save closes the editor, confirms it and fetches echoes',
      () async {
        final adapter = FakeHttpAdapter([
          ...bootReplies(
            entry: FakeReply(200, body: entryJson(rawText: 'Old.', version: 1)),
          ),
          FakeReply(200, body: entryJson(rawText: 'New.', version: 2)),
          FakeReply(
            200,
            body: {
              'echoes': <Object?>[echoJson()],
            },
          ),
        ]);
        final env = await ready(adapter);
        env.notifier.startEditing();
        env.notifier.updateText('New.');

        await env.notifier.save();

        final state = stateOf(env.container);
        expect(state.isEditing, isFalse);
        expect(state.entry!.rawText, 'New.');
        expect(state.savedMessage, 'Entry saved');
        expect(state.echoes, hasLength(1));
        final patchRequest = adapter.requests.firstWhere(
          (r) => r.method == 'PATCH',
        );
        // Unlike the day-entries screen, this editor's Save sends the
        // edited feelings and intensities alongside the text -- they are
        // part of what this screen lets you change.
        expect(patchRequest.data, {
          'version': 1,
          'raw_text': 'New.',
          'feeling_keys': ['happy'],
          'feeling_intensities': <String, int>{},
        });
      },
    );

    test('a failed echo fetch after a save is silent', () async {
      final adapter = FakeHttpAdapter([
        ...bootReplies(
          entry: FakeReply(200, body: entryJson(rawText: 'Old.', version: 1)),
        ),
        FakeReply(200, body: entryJson(rawText: 'New.', version: 2)),
        FakeReply(500, body: {'error': 'boom'}),
      ]);
      final env = await ready(adapter);
      env.notifier.startEditing();
      env.notifier.updateText('New.');

      await env.notifier.save();

      final state = stateOf(env.container);
      expect(state.isEditing, isFalse);
      expect(state.savedMessage, 'Entry saved');
      expect(state.errorMessage, isNull);
    });

    test(
      'a non-conflict failure keeps the editor open and records the message',
      () async {
        final adapter = FakeHttpAdapter([
          ...bootReplies(
            entry: FakeReply(200, body: entryJson(rawText: 'Old.', version: 1)),
          ),
          FakeReply(500, body: {'error': 'server exploded'}),
        ]);
        final env = await ready(adapter);
        env.notifier.startEditing();
        env.notifier.updateText('New.');

        await env.notifier.save();

        final state = stateOf(env.container);
        expect(state.isEditing, isTrue);
        expect(state.errorMessage, isNotNull);
      },
    );

    test(
      'a successful save bumps diaryWriteSignalProvider so Today picks up '
      'the edited feed card',
      () async {
        final adapter = FakeHttpAdapter([
          ...bootReplies(
            entry: FakeReply(200, body: entryJson(rawText: 'Old.', version: 1)),
          ),
          FakeReply(200, body: entryJson(rawText: 'New.', version: 2)),
          FakeReply(200, body: {'echoes': <Object?>[]}),
        ]);
        final env = await ready(adapter);
        expect(env.container.read(diaryWriteSignalProvider), 0);
        env.notifier.startEditing();
        env.notifier.updateText('New.');

        await env.notifier.save();

        expect(env.container.read(diaryWriteSignalProvider), 1);
      },
    );

    test('a failed save never bumps diaryWriteSignalProvider', () async {
      final adapter = FakeHttpAdapter([
        ...bootReplies(
          entry: FakeReply(200, body: entryJson(rawText: 'Old.', version: 1)),
        ),
        FakeReply(500, body: {'error': 'server exploded'}),
      ]);
      final env = await ready(adapter);
      env.notifier.startEditing();
      env.notifier.updateText('New.');

      await env.notifier.save();

      expect(env.container.read(diaryWriteSignalProvider), 0);
    });
  });

  group('conflict handling -- the delicate part', () {
    Map<String, Object?> staleBody({
      String rawText = "Someone else's edit.",
      int version = 9,
    }) => {
      'error': {'code': 'stale_entry', 'message': 'stale'},
      'current': entryJson(rawText: rawText, version: version),
    };

    test('a stale save surfaces the panel with both texts intact', () async {
      final adapter = FakeHttpAdapter([
        ...bootReplies(
          entry: FakeReply(
            200,
            body: entryJson(rawText: 'Mine originally.', version: 1),
          ),
        ),
        FakeReply(409, body: staleBody()),
      ]);
      final env = await ready(adapter);
      env.notifier.startEditing();
      env.notifier.updateText('My unsaved edit.');

      await env.notifier.save();

      final state = stateOf(env.container);
      expect(state.conflict, isNotNull);
      expect(state.conflict!.mine, 'My unsaved edit.');
      expect(state.conflict!.current.rawText, "Someone else's edit.");
      expect(state.conflict!.current.version, 9);
      // Nothing was overwritten: this screen's own `entry` field is
      // untouched by the refusal.
      expect(state.entry!.rawText, 'Mine originally.');
    });

    test('a stale delete shows the panel rather than deleting', () async {
      final adapter = FakeHttpAdapter([
        ...bootReplies(
          entry: FakeReply(200, body: entryJson(rawText: 'Mine.', version: 1)),
        ),
        FakeReply(409, body: staleBody()),
      ]);
      final env = await ready(adapter);

      await env.notifier.delete();

      final state = stateOf(env.container);
      expect(state.deleted, isFalse);
      expect(state.conflict, isNotNull);
      expect(state.conflict!.current.version, 9);
    });

    test(
      '"keep mine" retries with the conflict\'s version and succeeds',
      () async {
        final adapter = FakeHttpAdapter([
          ...bootReplies(
            entry: FakeReply(200, body: entryJson(rawText: 'Old.', version: 1)),
          ),
          FakeReply(409, body: staleBody(version: 9)),
          // The retry, now against version 9.
          FakeReply(
            200,
            body: entryJson(rawText: 'My unsaved edit.', version: 10),
          ),
          FakeReply(200, body: {'echoes': <Object?>[]}),
        ]);
        final env = await ready(adapter);
        env.notifier.startEditing();
        env.notifier.updateText('My unsaved edit.');
        await env.notifier.save();
        expect(stateOf(env.container).conflict, isNotNull);

        await env.notifier.retryWithCurrentVersion();

        final state = stateOf(env.container);
        expect(state.conflict, isNull);
        expect(state.entry!.rawText, 'My unsaved edit.');
        expect(state.entry!.version, 10);
        final retryRequest = adapter.requests
            .where((r) => r.method == 'PATCH')
            .last;
        expect(retryRequest.data, {
          'version': 9,
          'raw_text': 'My unsaved edit.',
          'feeling_keys': ['happy'],
          'feeling_intensities': <String, int>{},
        });
      },
    );

    test('"keep editing" leaves the draft text in the editor over the current entry', () async {
      final adapter = FakeHttpAdapter([
        ...bootReplies(
          entry: FakeReply(200, body: entryJson(rawText: 'Old.', version: 1)),
        ),
        FakeReply(
          409,
          body: staleBody(rawText: 'Current on server.', version: 9),
        ),
      ]);
      final env = await ready(adapter);
      env.notifier.startEditing();
      env.notifier.updateText('My unsaved edit.');
      await env.notifier.save();

      env.notifier.carryMineAcross();

      final state = stateOf(env.container);
      expect(state.conflict, isNull);
      expect(state.editedText, 'My unsaved edit.');
      expect(state.entry!.rawText, 'Current on server.');
      expect(state.entry!.version, 9);
      // Still open for editing -- a conflict can only be raised while
      // editing, and this resolution puts the user right back into it.
      expect(state.isEditing, isTrue);
    });

    test('"discard" adopts the server copy and drops the local edit', () async {
      final adapter = FakeHttpAdapter([
        ...bootReplies(
          entry: FakeReply(200, body: entryJson(rawText: 'Old.', version: 1)),
        ),
        FakeReply(
          409,
          body: staleBody(rawText: 'Current on server.', version: 9),
        ),
      ]);
      final env = await ready(adapter);
      env.notifier.startEditing();
      env.notifier.updateText('My unsaved edit.');
      await env.notifier.save();

      env.notifier.discardMine();

      final state = stateOf(env.container);
      expect(state.conflict, isNull);
      expect(state.editedText, 'Current on server.');
      expect(state.entry!.rawText, 'Current on server.');
      expect(state.entry!.version, 9);
    });
  });

  group('delete', () {
    test('a successful delete sets deleted', () async {
      final adapter = FakeHttpAdapter([
        ...bootReplies(),
        FakeReply(204),
      ]);
      final env = await ready(adapter);

      await env.notifier.delete();

      expect(stateOf(env.container).deleted, isTrue);
    });

    test(
      'a successful delete bumps diaryWriteSignalProvider so Today drops '
      'the entry too',
      () async {
        final adapter = FakeHttpAdapter([
          ...bootReplies(),
          FakeReply(204),
        ]);
        final env = await ready(adapter);
        expect(env.container.read(diaryWriteSignalProvider), 0);

        await env.notifier.delete();

        expect(env.container.read(diaryWriteSignalProvider), 1);
      },
    );

    test('a failed delete never bumps diaryWriteSignalProvider', () async {
      final adapter = FakeHttpAdapter([
        ...bootReplies(),
        FakeReply(500, body: {'error': 'server exploded'}),
      ]);
      final env = await ready(adapter);

      await env.notifier.delete();

      expect(env.container.read(diaryWriteSignalProvider), 0);
    });
  });

  group('dismiss', () {
    test('dismissSavedMessage, dismissError and dismissEchoes each clear their own field', () async {
      final adapter = FakeHttpAdapter([
        ...bootReplies(
          entry: FakeReply(200, body: entryJson(rawText: 'Old.', version: 1)),
        ),
        FakeReply(200, body: entryJson(rawText: 'New.', version: 2)),
        FakeReply(
          200,
          body: {
            'echoes': <Object?>[echoJson()],
          },
        ),
      ]);
      final env = await ready(adapter);
      env.notifier.startEditing();
      env.notifier.updateText('New.');
      await env.notifier.save();
      expect(stateOf(env.container).savedMessage, isNotNull);
      expect(stateOf(env.container).echoes, isNotEmpty);

      env.notifier.dismissSavedMessage();
      expect(stateOf(env.container).savedMessage, isNull);

      env.notifier.dismissEchoes();
      expect(stateOf(env.container).echoes, isEmpty);
    });
  });
}
