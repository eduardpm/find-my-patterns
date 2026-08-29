import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/calendar/day_entries_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

void main() {
  const date = CalendarDate(2026, 8, 5);
  const instantPoll = (
    interval: Duration.zero,
    timeout: Duration(milliseconds: 30),
  );

  ProviderContainer buildContainer(
    Harness harness, {
    AnalysisPollConfig pollConfig = instantPoll,
  }) {
    final container = ProviderContainer(
      overrides: [
        ...harness.baseOverrides,
        analysisPollConfigProvider.overrideWithValue(pollConfig),
        analysisPollDelayProvider.overrideWithValue((_) async {}),
      ],
      retry: Harness.noRetry,
    );
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
  Future<({ProviderContainer container, DayEntriesController notifier})> ready(
    FakeHttpAdapter adapter, {
    AnalysisPollConfig pollConfig = instantPoll,
  }) async {
    final container = buildContainer(
      configuredHarness(adapter),
      pollConfig: pollConfig,
    );
    container.read(dayEntriesControllerProvider(date));
    await pumpEventQueue();
    return (
      container: container,
      notifier: container.read(dayEntriesControllerProvider(date).notifier),
    );
  }

  DayEntriesState stateOf(ProviderContainer container) =>
      container.read(dayEntriesControllerProvider(date));

  test("build loads the day's entries", () async {
    final env = await ready(
      FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: {
            'entries': [
              entryJson(id: 'entry-1', rawText: 'First thing.'),
              entryJson(id: 'entry-2', rawText: 'Second thing.'),
            ],
          },
        ),
      ]),
    );

    final state = stateOf(env.container);
    expect(state.hasLoaded, isTrue);
    expect(state.entries.map((e) => e.id), ['entry-1', 'entry-2']);
  });

  test('a failed load still marks hasLoaded, leaving the list empty', () async {
    final env = await ready(
      FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(500, body: {'error': 'boom'}),
      ]),
    );

    final state = stateOf(env.container);
    expect(state.hasLoaded, isTrue);
    expect(state.entries, isEmpty);
    expect(state.errorMessage, isNotNull);
  });

  group('editing', () {
    test('startEditing seeds the draft from the stored text', () async {
      final env = await ready(
        FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          FakeReply(
            200,
            body: {
              'entries': [entryJson(id: 'entry-1', rawText: 'Stored text.')],
            },
          ),
        ]),
      );

      env.notifier.startEditing(stateOf(env.container).entries.single);

      final state = stateOf(env.container);
      expect(state.editingId, 'entry-1');
      expect(state.draft, 'Stored text.');
    });

    test('cancelEditing leaves the editor with nothing sent', () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: {
            'entries': [entryJson(id: 'entry-1', rawText: 'Stored text.')],
          },
        ),
      ]);
      final env = await ready(adapter);
      env.notifier.startEditing(stateOf(env.container).entries.single);
      final requestsBefore = adapter.requests.length;

      env.notifier.cancelEditing();

      final state = stateOf(env.container);
      expect(state.editingId, isNull);
      expect(state.draft, isEmpty);
      expect(adapter.requests.length, requestsBefore);
    });
  });

  group('saveEdit', () {
    test('does nothing for blank or unchanged text', () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: {
            'entries': [entryJson(id: 'entry-1', rawText: 'Same text.')],
          },
        ),
      ]);
      final env = await ready(adapter);
      env.notifier.startEditing(stateOf(env.container).entries.single);
      env.notifier.updateDraft('Same text.');
      final requestsBefore = adapter.requests.length;

      await env.notifier.saveEdit();

      expect(adapter.requests.length, requestsBefore);
      expect(stateOf(env.container).editingId, isNull);
    });

    test('sends only the text -- feelings are deliberately left out', () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: {
            'entries': [
              entryJson(id: 'entry-1', rawText: 'Old text.', version: 3),
            ],
          },
        ),
        // PATCH.
        FakeReply(
          200,
          body: entryJson(id: 'entry-1', rawText: 'New text.', version: 4),
        ),
        // Post-save refresh.
        FakeReply(
          200,
          body: {
            'entries': [
              entryJson(id: 'entry-1', rawText: 'New text.', version: 4),
            ],
          },
        ),
        // One poll: already done, nothing suggested.
        FakeReply(
          200,
          body: entryJson(id: 'entry-1', rawText: 'New text.', version: 4),
        ),
        // Post-poll refresh.
        FakeReply(
          200,
          body: {
            'entries': [
              entryJson(id: 'entry-1', rawText: 'New text.', version: 4),
            ],
          },
        ),
      ]);
      final env = await ready(adapter);
      env.notifier.startEditing(stateOf(env.container).entries.single);
      env.notifier.updateDraft('New text.');

      await env.notifier.saveEdit();

      final patchRequest = adapter.requests.firstWhere(
        (r) => r.method == 'PATCH',
      );
      expect(patchRequest.data, {'version': 3, 'raw_text': 'New text.'});
      final state = stateOf(env.container);
      expect(state.editingId, isNull);
      expect(state.isAnalysing, isFalse);
      expect(state.proposal, isNull);
    });

    test(
      'a stale save is refused with a fixed message and the editor closes',
      () async {
        final adapter = FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          FakeReply(
            200,
            body: {
              'entries': [
                entryJson(id: 'entry-1', rawText: 'Old text.', version: 3),
              ],
            },
          ),
          FakeReply(
            409,
            body: {
              'error': {'code': 'stale_entry', 'message': 'server says stale'},
              'current': entryJson(
                id: 'entry-1',
                rawText: "Someone else's edit.",
                version: 9,
              ),
            },
          ),
        ]);
        final env = await ready(adapter);
        env.notifier.startEditing(stateOf(env.container).entries.single);
        env.notifier.updateDraft('My edit.');

        await env.notifier.saveEdit();

        final state = stateOf(env.container);
        expect(state.editingId, isNull);
        expect(
          state.errorMessage,
          "This entry changed somewhere else, so your edit wasn't applied. "
          'Reopen it to see the current text.',
        );
      },
    );

    test(
      'polls getById until analysisPending clears, then offers the proposal',
      () async {
        final adapter = FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          FakeReply(
            200,
            body: {
              'entries': [
                entryJson(id: 'entry-1', rawText: 'Old.', version: 1),
              ],
            },
          ),
          // PATCH.
          FakeReply(
            200,
            body: entryJson(id: 'entry-1', rawText: 'New.', version: 2),
          ),
          // Post-save refresh.
          FakeReply(
            200,
            body: {
              'entries': [
                entryJson(id: 'entry-1', rawText: 'New.', version: 2),
              ],
            },
          ),
          // Poll 1: still pending.
          FakeReply(
            200,
            body: entryJson(
              id: 'entry-1',
              rawText: 'New.',
              version: 2,
              analysisPending: true,
            ),
          ),
          // Poll 2: done, with a proposed feeling.
          FakeReply(
            200,
            body: entryJson(
              id: 'entry-1',
              rawText: 'New.',
              version: 2,
              suggestedFeelings: [
                {'key': 'sad', 'confidence': 0.9},
              ],
            ),
          ),
          // Post-poll refresh.
          FakeReply(
            200,
            body: {
              'entries': [
                entryJson(id: 'entry-1', rawText: 'New.', version: 2),
              ],
            },
          ),
        ]);
        final env = await ready(adapter);
        env.notifier.startEditing(stateOf(env.container).entries.single);
        env.notifier.updateDraft('New.');

        await env.notifier.saveEdit();

        final state = stateOf(env.container);
        expect(state.isAnalysing, isFalse);
        expect(state.proposal!.entryId, 'entry-1');
        expect(state.proposal!.feelings.single.key, 'sad');
      },
    );

    test(
      'the wait is bounded -- it stops analysing without a proposal once the timeout passes',
      () async {
        final adapter = FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          FakeReply(
            200,
            body: {
              'entries': [
                entryJson(id: 'entry-1', rawText: 'Old.', version: 1),
              ],
            },
          ),
          // PATCH.
          FakeReply(
            200,
            body: entryJson(id: 'entry-1', rawText: 'New.', version: 2),
          ),
          // Post-save refresh.
          FakeReply(
            200,
            body: {
              'entries': [
                entryJson(id: 'entry-1', rawText: 'New.', version: 2),
              ],
            },
          ),
          // Exactly one poll fits inside a one-interval timeout, and it
          // never resolves -- proving the wait gives up rather than
          // hanging forever on a worker that never finishes.
          FakeReply(
            200,
            body: entryJson(
              id: 'entry-1',
              rawText: 'New.',
              version: 2,
              analysisPending: true,
            ),
          ),
        ]);
        final env = await ready(
          adapter,
          pollConfig: const (
            interval: Duration(milliseconds: 5),
            timeout: Duration(milliseconds: 5),
          ),
        );
        env.notifier.startEditing(stateOf(env.container).entries.single);
        env.notifier.updateDraft('New.');

        await env.notifier.saveEdit();

        final state = stateOf(env.container);
        expect(state.isAnalysing, isFalse);
        expect(state.proposal, isNull);
      },
    );
  });

  group('acceptProposal', () {
    test('confirms the proposed feelings and clears the proposal', () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: {
            'entries': [entryJson(id: 'entry-1', rawText: 'Text.', version: 2)],
          },
        ),
        // PATCH text.
        FakeReply(
          200,
          body: entryJson(id: 'entry-1', rawText: 'Text!', version: 3),
        ),
        // Post-save refresh.
        FakeReply(
          200,
          body: {
            'entries': [entryJson(id: 'entry-1', rawText: 'Text!', version: 3)],
          },
        ),
        // Poll: done, with a proposal.
        FakeReply(
          200,
          body: entryJson(
            id: 'entry-1',
            rawText: 'Text!',
            version: 3,
            suggestedFeelings: [
              {'key': 'sad', 'confidence': 0.9},
            ],
          ),
        ),
        // Post-poll refresh.
        FakeReply(
          200,
          body: {
            'entries': [entryJson(id: 'entry-1', rawText: 'Text!', version: 3)],
          },
        ),
        // acceptProposal's own PATCH.
        FakeReply(
          200,
          body: entryJson(id: 'entry-1', rawText: 'Text!', version: 4),
        ),
        // acceptProposal's own refresh.
        FakeReply(
          200,
          body: {
            'entries': [entryJson(id: 'entry-1', rawText: 'Text!', version: 4)],
          },
        ),
      ]);
      final env = await ready(adapter);
      env.notifier.startEditing(stateOf(env.container).entries.single);
      env.notifier.updateDraft('Text!');
      await env.notifier.saveEdit();
      expect(stateOf(env.container).proposal, isNotNull);

      await env.notifier.acceptProposal();

      final confirmRequest = adapter.requests.firstWhere(
        (r) => r.method == 'PATCH' && (r.data as Map)['feeling_keys'] != null,
      );
      expect(confirmRequest.data, {
        'version': 3,
        'feeling_keys': ['sad'],
      });
      expect(stateOf(env.container).proposal, isNull);
    });
  });
}
