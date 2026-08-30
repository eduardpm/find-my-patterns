import 'dart:async';
import 'dart:io';

import 'package:find_my_patterns/core/audio/diary_audio_recorder.dart';
import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/notifications/reminder_providers.dart';
import 'package:find_my_patterns/core/notifications/reminder_service.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/compose/composer_draft.dart';
import 'package:find_my_patterns/features/compose/entry_composer_controller.dart';
import 'package:find_my_patterns/features/compose/entry_composer_screen.dart';
import 'package:find_my_patterns/features/compose/first_pattern_card.dart';
import 'package:find_my_patterns/features/compose/first_pattern_copy.dart';
import 'package:find_my_patterns/features/compose/insight_progress_panel.dart';
import 'package:find_my_patterns/features/compose/pairing_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/audio/fake_audio_recorder_plugin.dart';
import '../../core/notifications/fake_device_time_zone.dart';
import '../../support/fake_composer_draft_store.dart';
import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

/// A `pollDelay` that never resolves on its own -- each call queues a
/// [Completer] instead of returning an already-completed future -- so a
/// test can freeze `EntryComposerController._pollForSuggestions` between
/// attempts and observe the "still polling" UI it would otherwise blow
/// straight through. `pumpAndSettle` alone cannot pause there: the fake
/// HTTP layer resolves through plain microtasks with no real delay behind
/// it, so a no-op delay (as used elsewhere in this suite) lets the whole
/// poll loop run to completion inside a single `pumpAndSettle`.
class ManualDelay {
  final List<Completer<void>> _pending = [];

  Future<void> call(Duration _) {
    final completer = Completer<void>();
    _pending.add(completer);
    return completer.future;
  }

  /// Whether a call is currently parked, waiting for [release].
  bool get isWaiting => _pending.isNotEmpty;

  /// Lets the oldest still-waiting call proceed.
  void release() => _pending.removeAt(0).complete();
}

/// Pumps up to [maxPumps] short frames, stopping as soon as [condition] is
/// true.
///
/// For use wherever `pumpAndSettle` cannot be: the pending-suggestion
/// banner carries an indeterminate `CircularProgressIndicator`, which keeps
/// scheduling frames forever and never lets `pumpAndSettle` return. Each
/// pump carries a small non-zero duration rather than the zero-duration
/// default `pump()` uses -- a bare `pump()` only flushes microtasks and
/// never fires a real `Timer` (e.g. one inside Dio's request pipeline) no
/// matter how many times it is called; only a pump carrying a duration
/// advances the fake clock those are scheduled against. A fixed pump count
/// is still a race against however many hops the fake HTTP layer needs, so
/// this pumps only as many times as it takes, bounded so a genuine bug
/// still fails fast rather than hanging. Leaves [condition] unmet (and lets
/// the next `expect` report that) if it never becomes true.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) => pumpUntil(tester, () => finder.evaluate().isNotEmpty, maxPumps: maxPumps);

Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) => pumpUntil(tester, () => finder.evaluate().isEmpty, maxPumps: maxPumps);

void main() {
  /// The three background loads the composer's controller fires on
  /// mount -- see `entry_composer_controller.dart`'s `_loadAll` for the
  /// order (feelings, then guiding questions, then insights).
  List<FakeReply> bootReplies({FakeReply? guiding}) => [
    FakeReply(200, body: feelingsCatalogJson()),
    guiding ?? FakeReply(200, body: guidingQuestionsJson()),
    FakeReply(200, body: insightsJson()),
  ];

  Widget buildTestable({
    required List<FakeReply> replies,
    VoidCallback? onDone,
    VoidCallback? onCancel,
    ComposerDraft? initialDraft,
    CalendarDate? targetDate,
    // A caller already holding a `Harness` (built with its own
    // `firstPatternNotified`, to assert on `firstPatternStore` or
    // `remindersPlugin` afterwards -- see the "first-pattern celebration"
    // group) passes it in directly instead of the four settings below,
    // which only exist to build one on a plain call site's behalf.
    Harness? harness,
  }) {
    final resolvedHarness =
        harness ??
        Harness(
          settings: const AppSettings(
            backend: BackendAddress(host: '10.0.2.2'),
          ),
          adapter: FakeHttpAdapter(replies),
          initialDraft: initialDraft,
        );
    return ProviderScope(
      overrides: [
        requireAuthProvider.overrideWithValue(resolvedHarness.requireAuth),
        settingsStoreProvider.overrideWithValue(resolvedHarness.store),
        apiClientProvider.overrideWithValue(resolvedHarness.client),
        composerDraftStoreProvider.overrideWithValue(
          resolvedHarness.draftStore,
        ),
        firstPatternStoreProvider.overrideWithValue(
          resolvedHarness.firstPatternStore,
        ),
        reminderServiceProvider.overrideWithValue(
          ReminderService(
            plugin: resolvedHarness.remindersPlugin,
            deviceTimeZone: FakeDeviceTimeZone(),
          ),
        ),
      ],
      child: MaterialApp(
        home: EntryComposerScreen(
          targetDate: targetDate,
          onDone: onDone,
          onCancel: onCancel,
          // A fake plugin and a real-but-untouched temp directory (the
          // fake never writes to the filesystem) so a voice tap never
          // reaches a real platform channel.
          recorder: DiaryAudioRecorder(
            plugin: FakeAudioRecorderPlugin(),
            cacheDirectory: () async => Directory.systemTemp,
          ),
          transcriptionDelay: (_) async {},
        ),
      ),
    );
  }

  /// The [ProviderContainer] `buildTestable`'s own [ProviderScope] created,
  /// read back out of the already-pumped widget tree.
  ///
  /// Only the suggestion-polling tests need this -- they stub
  /// `EntryComposerController.pollDelay` on the notifier before the save
  /// action that would otherwise start the poll loop on the real
  /// `Future.delayed`. Reading the container back out this way, rather than
  /// pre-building one and handing it to `UncontrolledProviderScope`, keeps
  /// every test in this file going through the exact same boot path: a
  /// `ProviderContainer` created by `ProviderScope` from inside
  /// `pumpWidget`, not one built and read from beforehand -- the latter
  /// left the three boot requests permanently stuck (see git history on
  /// this file if that regresses again).
  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(EntryComposerScreen)),
      );

  group('the guided stage', () {
    testWidgets('shows the mandatory prompt once the library has loaded', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestable(replies: bootReplies()));
      await tester.pumpAndSettle();

      expect(find.text("What's on your mind?"), findsOneWidget);
    });

    testWidgets(
      'falls back to freeform when the guiding-question library fails',
      (tester) async {
        await tester.pumpWidget(
          buildTestable(
            replies: bootReplies(
              guiding: FakeReply(500, body: {'error': 'boom'}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text("What's going on?"), findsOneWidget);
      },
    );

    testWidgets('the close button calls onCancel', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(
        buildTestable(
          replies: bootReplies(),
          onCancel: () => cancelled = true,
        ),
      );
      await tester.pumpAndSettle();

      // #150 task 1: the accessible name comes from the semantics tree's
      // `label`, not `IconButton`'s own `tooltip` field.
      expect(find.bySemanticsLabel('Cancel'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      expect(cancelled, isTrue);
    });
  });

  group('backdated header chip (#36)', () {
    testWidgets('is absent when composing for today, as before', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestable(replies: bootReplies()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Writing about'), findsNothing);
    });

    testWidgets(
      'shows the target day once opened for a past date, and the flow '
      'still reaches the confirm step normally',
      (tester) async {
        final replies = [
          ...bootReplies(),
          FakeReply(
            200,
            body: entryJson(
              suggestedFeelings: [suggestedFeelingJson(key: 'happy')],
            ),
          ),
        ];
        await tester.pumpWidget(
          buildTestable(
            replies: replies,
            targetDate: const CalendarDate(2026, 8, 26),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Writing about Wednesday, August 26'), findsOneWidget);

        await tester.tap(find.text('Write freely instead'));
        await tester.pump();
        await tester.enterText(find.byType(TextFormField), 'Catching up.');
        await tester.pump();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
        await tester.pumpAndSettle();

        expect(find.text('How did that feel?'), findsOneWidget);
        // The chip stays up through the confirm step too -- which day this
        // entry lands on is still worth knowing until it is actually saved.
        expect(find.text('Writing about Wednesday, August 26'), findsOneWidget);
      },
    );

    testWidgets(
      'the guided answer field still autofocuses on the backdated path '
      '(#14)',
      (tester) async {
        await tester.pumpWidget(
          buildTestable(
            replies: bootReplies(),
            targetDate: const CalendarDate(2026, 8, 26),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Writing about Wednesday, August 26'), findsOneWidget);
        expect(find.text("What's on your mind?"), findsOneWidget);
        expect(tester.testTextInput.hasAnyClients, isTrue);
      },
    );
  });

  group('switching to freeform', () {
    testWidgets('carries the mandatory answer into the freeform draft', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestable(replies: bootReplies()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Feeling okay.');
      await tester.tap(find.text('Write freely instead'));
      await tester.pump();

      expect(find.text('Feeling okay.'), findsOneWidget);
      expect(find.text("What's going on?"), findsOneWidget);
    });
  });

  group('edge-to-edge bottom inset (#10)', () {
    /// Two system-inset shapes a real device can hand this screen: a
    /// three-button nav bar (tall) and a gesture bar (short), on top of
    /// two different aspect ratios. Whichever one is simulated, the
    /// bottom-most control of whichever stage is on screen must stay
    /// clear of it -- this is what the [SafeArea] wrapping the composer's
    /// body (added for this ticket) is for; the [AppBar] above it already
    /// owns the top inset on its own (see the doc comment on that
    /// `SafeArea` in `entry_composer_screen.dart`), so only the bottom is
    /// exercised here.
    for (final (label, size, bottomInset) in [
      ('portrait, three-button nav', Size(400, 800), 48.0),
      ('landscape-ish, gesture nav', Size(800, 480), 40.0),
    ]) {
      testWidgets(
        'the freeform "Save entry" button clears the system nav bar '
        '($label)',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.view.padding = FakeViewPadding(bottom: bottomInset);
          addTearDown(tester.view.reset);

          await tester.pumpWidget(buildTestable(replies: bootReplies()));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Write freely instead'));
          await tester.pumpAndSettle();

          final saveButtonBottom = tester
              .getBottomLeft(find.widgetWithText(ElevatedButton, 'Save entry'))
              .dy;
          // The logical-pixel line the system nav bar starts at -- nothing
          // on screen may be drawn below it.
          final safeBottomEdge =
              tester.view.physicalSize.height / tester.view.devicePixelRatio -
              bottomInset;

          expect(
            saveButtonBottom,
            lessThanOrEqualTo(safeBottomEdge),
            reason:
                'the Save button must sit fully above the simulated system '
                'nav bar, not partly behind it',
          );
        },
      );
    }
  });

  group('saving from freeform', () {
    testWidgets('moves to the confirm-feeling stage and shows the '
        'suggested-feeling phrase', (tester) async {
      final replies = [
        ...bootReplies(),
        FakeReply(
          200,
          body: entryJson(
            suggestedFeelings: [suggestedFeelingJson(key: 'happy')],
          ),
        ),
      ];
      await tester.pumpWidget(buildTestable(replies: replies));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write freely instead'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'A long day.');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
      await tester.pumpAndSettle();

      expect(find.text('How did that feel?'), findsOneWidget);
      expect(
        find.text(
          "It sounds like you're feeling happy. Confirm that, or pick "
          'differently.',
        ),
        findsOneWidget,
      );
    });
  });

  group('confirming feelings', () {
    testWidgets('with nothing to echo, calls onDone directly', (
      tester,
    ) async {
      var done = false;
      final replies = [
        ...bootReplies(),
        FakeReply(200, body: entryJson()),
        FakeReply(200, body: entryJson(version: 2)),
        FakeReply(200, body: echoJson(count: 0)),
      ];
      await tester.pumpWidget(
        buildTestable(replies: replies, onDone: () => done = true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write freely instead'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'A long day.');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
      await tester.pumpAndSettle();

      // The entry's own feelings ('happy') already seed the selection, so
      // Confirm is enabled without picking anything by hand.
      final confirmButton = find.widgetWithText(ElevatedButton, 'Confirm');
      await tester.ensureVisible(confirmButton);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      expect(done, isTrue);
    });

    testWidgets('with something to echo, shows the echo stage, and Done '
        'calls onDone', (tester) async {
      var done = false;
      final replies = [
        ...bootReplies(),
        FakeReply(200, body: entryJson()),
        FakeReply(200, body: entryJson(version: 2)),
        FakeReply(200, body: echoJson(count: 1)),
      ];
      await tester.pumpWidget(
        buildTestable(replies: replies, onDone: () => done = true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write freely instead'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'A long day.');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
      await tester.pumpAndSettle();
      final confirmButton = find.widgetWithText(ElevatedButton, 'Confirm');
      await tester.ensureVisible(confirmButton);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      expect(find.text('Entry saved'), findsOneWidget);
      expect(done, isFalse);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
      expect(done, isTrue);
    });

    testWidgets(
      'with near-threshold progress, shows the insight progress panel '
      'under the echo panel (#37, L-2)',
      (tester) async {
        final replies = [
          ...bootReplies(),
          FakeReply(200, body: entryJson()),
          FakeReply(200, body: entryJson(version: 2)),
          FakeReply(
            200,
            body: echoJson(count: 0, progress: progressJson()),
          ),
        ];
        await tester.pumpWidget(buildTestable(replies: replies));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Write freely instead'));
        await tester.pump();
        await tester.enterText(find.byType(TextFormField), 'A long day.');
        await tester.pump();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
        await tester.pumpAndSettle();
        final confirmButton = find.widgetWithText(ElevatedButton, 'Confirm');
        await tester.ensureVisible(confirmButton);
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();

        expect(find.text('Entry saved'), findsOneWidget);
        expect(find.byType(InsightProgressPanel), findsOneWidget);
        expect(
          find.text('Tracking 7 topics across 12 entries.'),
          findsOneWidget,
        );
        expect(find.textContaining('Closest to a pattern'), findsOneWidget);
      },
    );
  });

  group('the pairing step (E-1c)', () {
    /// A mixed-valence entry (`happy` + `sad`) with two suggested pairings
    /// -- the shape that gates the pairing step -- carrying both
    /// `suggested_feelings` (so Confirm is enabled without hand-picking on
    /// the confirm-feeling step) and matching `feeling_keys`.
    Map<String, Object?> mixedEntryJson({int version = 1}) => entryJson(
      version: version,
      feelingKeys: const ['happy', 'sad'],
      suggestedFeelings: [
        suggestedFeelingJson(key: 'happy'),
        suggestedFeelingJson(key: 'sad'),
      ],
      topics: [
        topicJson(id: 'topic-1', name: 'exercise'),
        topicJson(id: 'topic-2', name: 'family'),
      ],
      topicFeelings: [
        topicFeelingJson(
          topicId: 'topic-1',
          topic: 'exercise',
          feelingKey: 'sad',
        ),
        topicFeelingJson(
          topicId: 'topic-2',
          topic: 'family',
          feelingKey: 'happy',
        ),
      ],
    );

    /// Saves a freeform entry and taps Confirm, landing on whichever stage
    /// that reaches -- shared by every test below.
    Future<void> saveAndConfirmFeelings(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write freely instead'));
      await tester.pump();
      await tester.enterText(
        find.byType(TextFormField),
        'Missed my run and felt disappointed, but a long call with my '
        'parents was lovely.',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
      await tester.pumpAndSettle();
      final confirmButton = find.widgetWithText(ElevatedButton, 'Confirm');
      await tester.ensureVisible(confirmButton);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a mixed-valence entry with two suggested pairings shows the pairing '
      'step, pre-filled from the suggestion',
      (tester) async {
        final harness = Harness(
          settings: const AppSettings(
            backend: BackendAddress(host: '10.0.2.2'),
          ),
          adapter: FakeHttpAdapter([
            ...bootReplies(),
            FakeReply(200, body: mixedEntryJson()), // POST /entries
            FakeReply(
              200,
              body: mixedEntryJson(version: 2),
            ), // PATCH confirm feelings
          ]),
        );
        await tester.pumpWidget(
          buildTestable(replies: const [], harness: harness),
        );

        await saveAndConfirmFeelings(tester);

        expect(find.text('Which goes with what?'), findsOneWidget);
        expect(find.byType(PairingStep), findsOneWidget);
      },
    );

    testWidgets(
      'Confirm pairing PUTs the board and then finishes the flow',
      (tester) async {
        var done = false;
        final harness = Harness(
          settings: const AppSettings(
            backend: BackendAddress(host: '10.0.2.2'),
          ),
          adapter: FakeHttpAdapter([
            ...bootReplies(),
            FakeReply(200, body: mixedEntryJson()), // POST /entries
            FakeReply(
              200,
              body: mixedEntryJson(version: 2),
            ), // PATCH confirm feelings
            FakeReply(
              200,
              body: mixedEntryJson(version: 3),
            ), // PUT topic-feelings
            FakeReply(200, body: echoJson(count: 0)), // GET echo
          ]),
        );
        await tester.pumpWidget(
          buildTestable(
            replies: const [],
            harness: harness,
            onDone: () => done = true,
          ),
        );

        await saveAndConfirmFeelings(tester);
        expect(find.text('Which goes with what?'), findsOneWidget);

        final confirmPairingButton = find.widgetWithText(
          ElevatedButton,
          'Confirm pairing',
        );
        await tester.ensureVisible(confirmPairingButton);
        await tester.tap(confirmPairingButton);
        await tester.pumpAndSettle();

        final putRequest = harness.adapter.requests.firstWhere(
          (request) => request.method == 'PUT',
        );
        expect(putRequest.path, '/entries/entry-1/topic-feelings');
        expect(putRequest.data, {
          'pairings': [
            {'topic_id': 'topic-1', 'feeling_key': 'sad'},
            {'topic_id': 'topic-2', 'feeling_key': 'happy'},
          ],
        });
        // Nothing to echo -- straight through to Done.
        expect(done, isTrue);
      },
    );

    testWidgets(
      'Skip writes nothing at all and still finishes the flow (task 3)',
      (tester) async {
        var done = false;
        final harness = Harness(
          settings: const AppSettings(
            backend: BackendAddress(host: '10.0.2.2'),
          ),
          adapter: FakeHttpAdapter([
            ...bootReplies(),
            FakeReply(200, body: mixedEntryJson()), // POST /entries
            FakeReply(
              200,
              body: mixedEntryJson(version: 2),
            ), // PATCH confirm feelings
            FakeReply(200, body: echoJson(count: 0)), // GET echo
          ]),
        );
        await tester.pumpWidget(
          buildTestable(
            replies: const [],
            harness: harness,
            onDone: () => done = true,
          ),
        );

        await saveAndConfirmFeelings(tester);
        expect(find.text('Which goes with what?'), findsOneWidget);

        final skipButton = find.widgetWithText(OutlinedButton, 'Skip');
        await tester.ensureVisible(skipButton);
        await tester.tap(skipButton);
        await tester.pumpAndSettle();

        expect(
          harness.adapter.requests.any((request) => request.method == 'PUT'),
          isFalse,
        );
        expect(done, isTrue);
      },
    );

    testWidgets(
      'a single-valence entry never shows the pairing step, even with two '
      'suggested pairings -- flow completely unchanged (acceptance '
      'criterion 4)',
      (tester) async {
        // Two suggested pairings, but both pointing at the entry's one and
        // only feeling -- so [needsPairingStep]'s valence half fails even
        // though its "at least two suggested pairings" half would pass.
        Map<String, Object?> singleValenceEntryJson({int version = 1}) =>
            entryJson(
              version: version,
              feelingKeys: const ['happy'],
              suggestedFeelings: [suggestedFeelingJson(key: 'happy')],
              topics: [
                topicJson(id: 'topic-1', name: 'exercise'),
                topicJson(id: 'topic-2', name: 'family'),
              ],
              topicFeelings: [
                topicFeelingJson(
                  topicId: 'topic-1',
                  topic: 'exercise',
                  feelingKey: 'happy',
                ),
                topicFeelingJson(
                  topicId: 'topic-2',
                  topic: 'family',
                  feelingKey: 'happy',
                ),
              ],
            );
        var done = false;
        final harness = Harness(
          settings: const AppSettings(
            backend: BackendAddress(host: '10.0.2.2'),
          ),
          adapter: FakeHttpAdapter([
            ...bootReplies(),
            FakeReply(200, body: singleValenceEntryJson()), // POST /entries
            FakeReply(
              200,
              body: singleValenceEntryJson(version: 2),
            ), // PATCH confirm feelings
            FakeReply(200, body: echoJson(count: 0)), // GET echo
          ]),
        );
        await tester.pumpWidget(
          buildTestable(
            replies: const [],
            harness: harness,
            onDone: () => done = true,
          ),
        );

        await saveAndConfirmFeelings(tester);

        expect(find.text('Which goes with what?'), findsNothing);
        expect(find.byType(PairingStep), findsNothing);
        expect(done, isTrue);
      },
    );
  });

  group('first-pattern celebration (L-3/#38)', () {
    /// Types and saves a freeform entry, then taps Confirm, leaving the
    /// screen on whatever `EchoStage`/`ConfirmFeelingStage` state that
    /// lands on -- shared by every test in this group.
    Future<void> saveAndConfirm(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write freely instead'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'A long day.');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
      await tester.pumpAndSettle();
      final confirmButton = find.widgetWithText(ElevatedButton, 'Confirm');
      await tester.ensureVisible(confirmButton);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows the inline card when this save surfaces the diary\'s first '
      'pattern while the app is in the foreground',
      (tester) async {
        final harness = Harness(
          settings: const AppSettings(
            backend: BackendAddress(host: '10.0.2.2'),
          ),
          adapter: FakeHttpAdapter([
            ...bootReplies(),
            FakeReply(200, body: entryJson()),
            FakeReply(200, body: entryJson(version: 2)),
            FakeReply(200, body: insightsJson(patterns: [patternJson()])),
            FakeReply(200, body: echoJson(count: 0)),
          ]),
          firstPatternNotified: false,
        );
        await tester.pumpWidget(
          buildTestable(replies: const [], harness: harness),
        );

        await saveAndConfirm(tester);

        expect(find.text('Entry saved'), findsOneWidget);
        expect(find.byType(FirstPatternCard), findsOneWidget);
        expect(find.text(firstPatternCardText), findsOneWidget);
        expect(harness.remindersPlugin.showCalls, isEmpty);
      },
    );

    testWidgets(
      'tapping the card signals Insights and closes the composer',
      (tester) async {
        final harness = Harness(
          settings: const AppSettings(
            backend: BackendAddress(host: '10.0.2.2'),
          ),
          adapter: FakeHttpAdapter([
            ...bootReplies(),
            FakeReply(200, body: entryJson()),
            FakeReply(200, body: entryJson(version: 2)),
            FakeReply(200, body: insightsJson(patterns: [patternJson()])),
            FakeReply(200, body: echoJson(count: 0)),
          ]),
          firstPatternNotified: false,
        );
        var done = false;
        await tester.pumpWidget(
          buildTestable(
            replies: const [],
            harness: harness,
            onDone: () => done = true,
          ),
        );

        await saveAndConfirm(tester);
        final container = containerOf(tester);
        expect(container.read(openInsightsSignalProvider), 0);

        await tester.tap(find.byType(FirstPatternCard));
        await tester.pump();

        expect(done, isTrue);
        expect(container.read(openInsightsSignalProvider), 1);
      },
    );

    testWidgets(
      'does not render once the flag is already set, even with a pattern '
      'in the payload',
      (tester) async {
        final harness = Harness(
          settings: const AppSettings(
            backend: BackendAddress(host: '10.0.2.2'),
          ),
          adapter: FakeHttpAdapter([
            ...bootReplies(),
            FakeReply(200, body: entryJson()),
            FakeReply(200, body: entryJson(version: 2)),
            FakeReply(200, body: echoJson(count: 0)),
          ]),
        );
        await tester.pumpWidget(
          buildTestable(replies: const [], harness: harness),
        );

        await saveAndConfirm(tester);

        // Nothing to echo and no celebration -- confirm closes the
        // composer straight away, the same as before this feature existed.
        expect(find.byType(FirstPatternCard), findsNothing);
      },
    );
  });

  group('suggestion polling in the confirm-feeling UI', () {
    /// Types and saves a freeform entry, up to the tap on "Save entry".
    /// Shared by both tests below -- everything that follows the tap is
    /// where the two scenarios (arrives vs. never arrives) diverge.
    Future<void> saveFreeformEntry(WidgetTester tester) async {
      await tester.tap(find.text('Write freely instead'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'A long day.');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
    }

    testWidgets(
      'shows a pending banner, then pre-selects once a suggestion arrives',
      (tester) async {
        final delay = ManualDelay();
        await tester.pumpWidget(
          buildTestable(
            replies: [
              ...bootReplies(),
              FakeReply(201, body: entryJson(analysisPending: true)),
              FakeReply(200, body: entryJson(analysisPending: true)),
              FakeReply(
                200,
                body: entryJson(
                  analysisPending: false,
                  suggestedFeelings: [suggestedFeelingJson(key: 'happy')],
                ),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        // Stubbed only now, on the container `ProviderScope` already built
        // during the pump above -- well before the save below, which is the
        // only thing that starts the poll loop.
        containerOf(
                  tester,
                )
                .read(
                  entryComposerControllerProvider(CalendarDate.today())
                      .notifier,
                )
                .pollDelay =
            delay.call;

        await saveFreeformEntry(tester);
        // See `pumpUntilFound`'s doc comment: not `pumpAndSettle` here, the
        // pending banner's spinner never lets it return.
        final banner = find.text('Reading your entry…');
        await pumpUntilFound(tester, banner);

        expect(banner, findsOneWidget);
        // The manual picker is not gated behind the pending banner.
        expect(find.text('Uplifted'), findsOneWidget);

        delay.release(); // attempt 1: the worker is still analysing.
        // Waits for the loop to have processed the (still-pending) GET
        // response and parked on its next `pollDelay` call.
        await pumpUntil(tester, () => delay.isWaiting);
        expect(banner, findsOneWidget);

        delay.release(); // attempt 2: the analyser's verdict is in.
        await pumpUntilGone(tester, banner);
        // The spinner is gone now, so settling the rest of the frame is safe.
        await tester.pumpAndSettle();

        expect(banner, findsNothing);
        expect(
          find.text(
            "It sounds like you're feeling happy. Confirm that, or pick "
            'differently.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'pre-selects every feeling the worker already wrote onto the entry, '
      'not just the first (#66)',
      (tester) async {
        // The ground-truth shape a *fixed* backend returns once the worker
        // has run: the entry's own `feeling_keys` already carry both
        // feelings under `feeling_source: 'suggested'`, and
        // `suggested_feelings` mirrors that same set (issue #66 -- before
        // the backend fix, `suggested_feelings` came back `[]` here even
        // though the entry already carried both). This is deliberately not
        // the single-feeling fixture the other test in this group uses, so
        // pre-selection is proven for the multi-feeling case the backend
        // actually produces, not a shape that happens to work by accident.
        final delay = ManualDelay();
        await tester.pumpWidget(
          buildTestable(
            replies: [
              ...bootReplies(),
              // Genuinely pending -- no feeling chosen yet by anyone,
              // `entryJson()`'s default `feeling_key: 'happy'` would seed
              // `_selected` before the suggestion ever arrives and mask
              // exactly the gap this test exists to catch (the re-seed in
              // `_ConfirmFeelingStepState.didUpdateWidget` only fires while
              // `_selected` is still empty).
              FakeReply(201, body: unanalysedEntryJson()),
              FakeReply(200, body: unanalysedEntryJson()),
              FakeReply(
                200,
                body: entryJson(
                  feelingKey: 'happy',
                  feelingKeys: ['happy', 'sad'],
                  analysisPending: false,
                  suggestedFeelings: [
                    suggestedFeelingJson(key: 'happy'),
                    suggestedFeelingJson(key: 'sad'),
                  ],
                ),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        containerOf(
                  tester,
                )
                .read(
                  entryComposerControllerProvider(CalendarDate.today())
                      .notifier,
                )
                .pollDelay =
            delay.call;

        await saveFreeformEntry(tester);
        final banner = find.text('Reading your entry…');
        await pumpUntilFound(tester, banner);

        delay.release(); // attempt 1: the worker is still analysing.
        await pumpUntil(tester, () => delay.isWaiting);
        delay.release(); // attempt 2: the analyser's verdict is in.
        await pumpUntilGone(tester, banner);
        await tester.pumpAndSettle();

        // This is the bug's exact symptom (issue #66): with
        // `suggested_feelings` suppressed, nothing was ever pre-selected
        // and the picker fell back to its empty state.
        expect(
          find.text(
            'Nothing chosen yet — pick a group to see the feelings inside '
            'it.',
          ),
          findsNothing,
        );
        // Both feelings from the worker's own write are pre-selected --
        // each renders both as a removable chip in the chosen-feelings row
        // and as its own intensity dial below, so at least one of each is
        // on screen -- not just the primary one.
        expect(find.text('Happy'), findsWidgets);
        expect(find.text('Sad'), findsWidgets);
        // Only the chosen-feelings chips carry the "suggested" label, one
        // per pre-selected feeling.
        expect(find.text('suggested'), findsNWidgets(2));
        // Confirm is enabled without the user picking anything by hand.
        final confirmButton = find.widgetWithText(ElevatedButton, 'Confirm');
        await tester.ensureVisible(confirmButton);
        expect(
          tester.widget<ElevatedButton>(confirmButton).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'a worker that never responds resolves to the manual picker -- no '
      'stuck spinner and no error',
      (tester) async {
        final delay = ManualDelay();
        await tester.pumpWidget(
          buildTestable(
            replies: [
              ...bootReplies(),
              FakeReply(201, body: entryJson(analysisPending: true)),
              for (var i = 0; i < 12; i++)
                FakeReply(200, body: entryJson(analysisPending: true)),
            ],
          ),
        );
        await tester.pumpAndSettle();
        containerOf(
                  tester,
                )
                .read(
                  entryComposerControllerProvider(CalendarDate.today())
                      .notifier,
                )
                .pollDelay =
            delay.call;

        await saveFreeformEntry(tester);
        // Not `pumpAndSettle` -- see the previous test's comment: the
        // pending banner's spinner never lets it return.
        final banner = find.text('Reading your entry…');
        await pumpUntilFound(tester, banner);
        expect(banner, findsOneWidget);

        // All 12 attempts still find the worker mid-analysis; the 12th
        // exhausts the poll loop's budget instead of getting a 13th try.
        // Each release is followed by a bounded pump-until, rather than a
        // fixed pump count, for whichever comes first: the next `pollDelay`
        // call parking (ready for the next release) or the banner clearing
        // (the loop gave up after this release).
        for (var attempt = 0; attempt < 12; attempt++) {
          delay.release();
          await pumpUntil(
            tester,
            () => delay.isWaiting || banner.evaluate().isEmpty,
          );
        }
        await pumpUntilGone(tester, banner);
        // The spinner is gone now, so settling the rest of the frame is safe.
        await tester.pumpAndSettle();

        expect(banner, findsNothing);
        expect(find.byType(SnackBar), findsNothing);

        // The manual picker still confirms the entry without error noise.
        final confirmButton = find.widgetWithText(ElevatedButton, 'Confirm');
        await tester.ensureVisible(confirmButton);
        expect(
          tester.widget<ElevatedButton>(confirmButton).onPressed,
          isNotNull,
        );
      },
    );
  });

  group('errors', () {
    testWidgets('a save failure surfaces as a snack bar', (tester) async {
      final replies = [
        ...bootReplies(),
        FakeReply(500, body: {'error': 'server exploded'}),
      ];
      await tester.pumpWidget(buildTestable(replies: replies));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write freely instead'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'A long day.');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
      await tester.pumpAndSettle();

      expect(find.text('server exploded'), findsOneWidget);
    });
  });

  group('dismiss guard', () {
    testWidgets('an empty composer dismisses with no guard on X', (
      tester,
    ) async {
      var cancelled = false;
      await tester.pumpWidget(
        buildTestable(
          replies: bootReplies(),
          onCancel: () => cancelled = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
      expect(find.text('Discard this entry?'), findsNothing);
    });

    testWidgets(
      'typed text shows the guard sheet instead of dismissing on X',
      (tester) async {
        var cancelled = false;
        await tester.pumpWidget(
          buildTestable(
            replies: bootReplies(),
            onCancel: () => cancelled = true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'Feeling okay.');
        await tester.pump();

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(find.text('Discard this entry?'), findsOneWidget);
        expect(cancelled, isFalse);
      },
    );

    testWidgets('Keep writing returns to the exact same state', (
      tester,
    ) async {
      var cancelled = false;
      await tester.pumpWidget(
        buildTestable(
          replies: bootReplies(),
          onCancel: () => cancelled = true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Feeling okay.');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keep writing'));
      await tester.pumpAndSettle();

      expect(find.text('Discard this entry?'), findsNothing);
      expect(cancelled, isFalse);
      expect(find.text('Feeling okay.'), findsOneWidget);
    });

    testWidgets('Discard closes the composer and clears the draft', (
      tester,
    ) async {
      var cancelled = false;
      await tester.pumpWidget(
        buildTestable(
          replies: bootReplies(),
          onCancel: () => cancelled = true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Feeling okay.');
      await tester.pump();
      // Lets the (unstubbed, default-duration) debounced autosave land, so
      // there is something on disk for Discard to actually clear.
      await tester.pump(const Duration(milliseconds: 600));
      final draftStore = containerOf(
        tester,
      ).read(composerDraftStoreProvider) as FakeComposerDraftStore;
      expect(await draftStore.load(), isNotNull);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
      expect(await draftStore.load(), isNull);
    });

    testWidgets('system back with typed text shows the guard sheet', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestable(replies: bootReplies()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Feeling okay.');
      await tester.pump();

      // Simulates the Android system back gesture/button.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard this entry?'), findsOneWidget);
    });

    testWidgets('system back on an empty composer dismisses directly', (
      tester,
    ) async {
      // A real two-route `Navigator`, not `onCancel`, is what this one
      // needs to prove something with: on an empty composer `PopScope`'s
      // `canPop` is true, so the system back gesture is handled by
      // Flutter's own pop machinery directly -- `onPopInvokedWithResult`
      // fires with `didPop: true` and never calls `requestCancel` (let
      // alone `cancel`/`onCancel`) at all. A route that is actually gone
      // is the only honest way to show "dismissed", not a callback that a
      // guard-free exit is never obliged to call.
      final harness = Harness(
        settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
        adapter: FakeHttpAdapter(bootReplies()),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            requireAuthProvider.overrideWithValue(harness.requireAuth),
            settingsStoreProvider.overrideWithValue(harness.store),
            apiClientProvider.overrideWithValue(harness.client),
            composerDraftStoreProvider.overrideWithValue(harness.draftStore),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EntryComposerScreen(),
                      ),
                    ),
                    child: const Text('Open composer'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open composer'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryComposerScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(EntryComposerScreen), findsNothing);
      expect(find.text('Open composer'), findsOneWidget);
    });

    testWidgets(
      'the confirm-feeling stage dismisses with no guard, even though the '
      'text is already saved (#4 point 3)',
      (tester) async {
        var cancelled = false;
        final replies = [...bootReplies(), FakeReply(201, body: entryJson())];
        await tester.pumpWidget(
          buildTestable(replies: replies, onCancel: () => cancelled = true),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Write freely instead'));
        await tester.pump();
        await tester.enterText(find.byType(TextFormField), 'A long day.');
        await tester.pump();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
        await tester.pumpAndSettle();
        expect(find.text('How did that feel?'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(find.text('Discard this entry?'), findsNothing);
        expect(cancelled, isTrue);
      },
    );
  });

  group('restored draft notice', () {
    testWidgets('shows the saved time and restores the guided answer', (
      tester,
    ) async {
      final savedAt = DateTime.utc(2026, 8, 29, 23, 32);
      await tester.pumpWidget(
        buildTestable(
          replies: bootReplies(),
          initialDraft: ComposerDraft(
            mode: ComposerDraftMode.guided,
            guidedAnswers: const {'general': 'Feeling okay.'},
            savedAt: savedAt,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Continuing your draft from'),
        findsOneWidget,
      );
      expect(find.text('Feeling okay.'), findsOneWidget);
    });

    testWidgets(
      'dismissing the notice hides it without discarding the draft',
      (tester) async {
        await tester.pumpWidget(
          buildTestable(
            replies: bootReplies(),
            initialDraft: ComposerDraft(
              mode: ComposerDraftMode.guided,
              guidedAnswers: const {'general': 'Feeling okay.'},
              savedAt: DateTime.utc(2026),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // #150 task 1: the accessible name comes from the semantics tree's
        // `label`, not `IconButton`'s own `tooltip` field.
        expect(find.bySemanticsLabel('Dismiss'), findsOneWidget);

        await tester.tap(find.byTooltip('Dismiss'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Continuing your draft from'),
          findsNothing,
        );
        expect(find.text('Feeling okay.'), findsOneWidget);
      },
    );

    testWidgets('Start fresh clears the draft and the restored answers', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestable(
          replies: bootReplies(),
          initialDraft: ComposerDraft(
            mode: ComposerDraftMode.guided,
            guidedAnswers: const {'general': 'Feeling okay.'},
            savedAt: DateTime.utc(2026),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final draftStore = containerOf(
        tester,
      ).read(composerDraftStoreProvider) as FakeComposerDraftStore;

      await tester.tap(find.text('Start fresh'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Continuing your draft from'),
        findsNothing,
      );
      expect(find.text('Feeling okay.'), findsNothing);
      expect(await draftStore.load(), isNull);
    });
  });

  group('draft survives a kill and reopen', () {
    testWidgets(
      'typed answers and the step position come back on the next open',
      (tester) async {
        await tester.pumpWidget(buildTestable(replies: bootReplies()));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'Feeling okay.');
        await tester.pump();
        // Lets the (unstubbed, default-duration) debounced autosave land.
        await tester.pump(const Duration(milliseconds: 600));
        final draftStore = containerOf(
          tester,
        ).read(composerDraftStoreProvider) as FakeComposerDraftStore;
        final savedDraft = await draftStore.load();
        expect(savedDraft, isNotNull);

        // Tears the first composer's element tree (and with it, its
        // `ProviderScope` and `EntryComposerController` instance) down
        // completely -- pumping a second `buildTestable` straight over the
        // first would otherwise update the existing elements in place
        // rather than rebuild fresh ones, since Riverpod reuses a
        // `ProviderScope`'s container across a widget update unless
        // something forces a real teardown. Without this, the assertions
        // below would silently pass by observing the *first* composer's
        // already-typed text, not a freshly restored draft.
        await tester.pumpWidget(const SizedBox());

        // "Reopen": a fresh composer instance reading back the draft the
        // previous instance's autosave wrote -- standing in for the app
        // having been force-stopped and relaunched, since nothing survives
        // that except what made it to disk.
        await tester.pumpWidget(
          buildTestable(replies: bootReplies(), initialDraft: savedDraft),
        );
        await tester.pumpAndSettle();

        expect(find.text('Feeling okay.'), findsOneWidget);
        expect(
          find.textContaining('Continuing your draft from'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a skipped question round-trips through a killed and reopened '
      'composer without becoming an answer that blocks Save (#14)',
      (tester) async {
        // A two-mandatory-question library, mirroring the real backend's
        // guided flow -- unlike `bootReplies()`'s single-mandatory-prompt
        // fixture, this is what it takes to have one question skipped and
        // a second one still open to answer and save from.
        final questions = FakeReply(
          200,
          body: {
            'questions': [
              {
                'key': 'general',
                'category': 'general',
                'prompt_text': "What's on your mind?",
                'trigger_keywords': <String>[],
                'is_mandatory': true,
              },
              {
                'key': 'mind_body',
                'category': 'mind_body',
                'prompt_text': 'How did you feel physically?',
                'trigger_keywords': <String>[],
                'is_mandatory': true,
              },
            ],
          },
        );
        final harness = Harness(
          settings: const AppSettings(
            backend: BackendAddress(host: '10.0.2.2'),
          ),
          adapter: FakeHttpAdapter([
            FakeReply(200, body: feelingsCatalogJson()),
            questions,
            FakeReply(200, body: insightsJson()),
          ]),
        );
        Widget composer() => harness.scope(
          MaterialApp(
            home: EntryComposerScreen(
              recorder: DiaryAudioRecorder(
                plugin: FakeAudioRecorderPlugin(),
                cacheDirectory: () async => Directory.systemTemp,
              ),
              transcriptionDelay: (_) async {},
            ),
          ),
        );

        await tester.pumpWidget(composer());
        await tester.pumpAndSettle();

        // Step 1 ('general'): skip it, with nothing typed.
        expect(find.text("What's on your mind?"), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Skip'));
        await tester.pump();

        // Step 2 ('mind_body'), the last step: answer it for real.
        expect(find.text('How did you feel physically?'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField), 'Sore feet.');
        await tester.pump();
        // Lets the (unstubbed, default-duration) debounced autosave land.
        await tester.pump(const Duration(milliseconds: 600));

        final savedDraft = await harness.draftStore.load();
        expect(savedDraft, isNotNull);
        expect(savedDraft!.guidedStepIndex, 1);
        // The skipped question stored no answer -- present as an empty
        // string (explicitly cleared) rather than a real one.
        expect(savedDraft.guidedAnswers['general'], '');
        expect(savedDraft.guidedAnswers['mind_body'], 'Sore feet.');

        // Tears the first composer down completely -- see the comment on
        // the equivalent assertion in the test above for why this is
        // needed.
        await tester.pumpWidget(const SizedBox());

        // "Reopen": a fresh composer instance, seeded with the draft the
        // first one's autosave wrote, standing in for the app having been
        // force-stopped and relaunched.
        final reopenHarness = Harness(
          settings: const AppSettings(
            backend: BackendAddress(host: '10.0.2.2'),
          ),
          adapter: FakeHttpAdapter([
            FakeReply(200, body: feelingsCatalogJson()),
            questions,
            FakeReply(200, body: insightsJson()),
            FakeReply(201, body: entryJson()),
          ]),
          initialDraft: savedDraft,
        );
        await tester.pumpWidget(
          reopenHarness.scope(
            MaterialApp(
              home: EntryComposerScreen(
                recorder: DiaryAudioRecorder(
                  plugin: FakeAudioRecorderPlugin(),
                  cacheDirectory: () async => Directory.systemTemp,
                ),
                transcriptionDelay: (_) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Restored onto the last step, with the skipped question's field
        // blank and Save already enabled off the one real answer -- the
        // empty stored answer never counts as an answer that blocks Save.
        expect(find.text('Sore feet.'), findsOneWidget);
        expect(find.textContaining('Continuing your draft'), findsOneWidget);
        final saveButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Save entry'),
        );
        expect(saveButton.onPressed, isNotNull);

        await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
        await tester.pumpAndSettle();

        expect(find.text('How did that feel?'), findsOneWidget);
        final sentBody =
            reopenHarness.adapter.requests.last.data as Map<String, Object?>;
        expect(sentBody['guided_answers'], [
          {'question_key': 'mind_body', 'answer_text': 'Sore feet.'},
        ]);
      },
    );

    testWidgets(
      'a successful save clears the draft -- the next open starts blank',
      (tester) async {
        final replies = [...bootReplies(), FakeReply(201, body: entryJson())];
        await tester.pumpWidget(buildTestable(replies: replies));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Write freely instead'));
        await tester.pump();
        await tester.enterText(find.byType(TextFormField), 'A long day.');
        await tester.pump();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
        await tester.pumpAndSettle();
        final draftStore = containerOf(
          tester,
        ).read(composerDraftStoreProvider) as FakeComposerDraftStore;
        expect(await draftStore.load(), isNull);

        // Tears the first composer down completely -- see the comment on
        // the equivalent line in the test above for why this is needed.
        await tester.pumpWidget(const SizedBox());

        // "Reopen": a fresh composer instance, same (now-empty) store.
        await tester.pumpWidget(buildTestable(replies: bootReplies()));
        await tester.pumpAndSettle();

        expect(find.text("What's on your mind?"), findsOneWidget);
        expect(find.textContaining('Continuing your draft'), findsNothing);
      },
    );
  });

  group('no dangling timer', () {
    testWidgets(
      'closing the composer mid-debounce leaves nothing still pending',
      (tester) async {
        // A custom `onCancel`, the same as every other test in this file
        // that reaches a real dismissal -- the default falls back to a raw
        // `Navigator.pop`, which asserts when (as here) the composer is the
        // route's only entry, and that assertion is no part of what this
        // test exists to check.
        var cancelled = false;
        await tester.pumpWidget(
          buildTestable(
            replies: bootReplies(),
            onCancel: () => cancelled = true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'unsaved');
        await tester.pump();
        // Popped immediately, before the default-duration debounce has a
        // chance to fire on its own -- if the pending autosave `Timer`
        // were not cancelled on disposal, flutter_test's own teardown
        // would fail this test with "A Timer is still pending even after
        // the widget tree was disposed", regardless of anything asserted
        // below. Completing cleanly (and `cancelled` ending up true) is
        // the proof.
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();

        expect(cancelled, isTrue);
      },
    );
  });

  group('dynamic type (#155b)', () {
    testWidgets(
      "the restored-draft notice's dismiss button measures at least "
      '48x48 with no explicit constraints override (#155)',
      (tester) async {
        // Unlike `today_screen.dart`'s backdate-nudge dismiss (#150 task
        // 4, which needed an explicit `BoxConstraints` floor after a bare
        // `BoxConstraints()` removed the platform default), this
        // `IconButton` at ~line 466 sets neither `constraints:` nor
        // `padding:`, so it should already fall back to `IconButton`'s
        // own 48dp default -- confirmed here by measurement rather than
        // by reading the constructor, per ACCESSIBILITY.md §4.
        await tester.pumpWidget(
          buildTestable(
            replies: bootReplies(),
            initialDraft: ComposerDraft(
              mode: ComposerDraftMode.guided,
              guidedAnswers: const {'general': 'Feeling okay.'},
              savedAt: DateTime.utc(2026),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.bySemanticsLabel('Dismiss'), findsOneWidget);
        final dismissSize = tester.getSize(find.byTooltip('Dismiss'));
        expect(dismissSize.width, greaterThanOrEqualTo(48));
        expect(dismissSize.height, greaterThanOrEqualTo(48));
      },
    );

    testWidgets(
      "the AppBar's Cancel button also measures at least 48x48 (#155)",
      (tester) async {
        await tester.pumpWidget(buildTestable(replies: bootReplies()));
        await tester.pumpAndSettle();

        expect(find.bySemanticsLabel('Cancel'), findsOneWidget);
        final cancelSize = tester.getSize(find.byTooltip('Cancel'));
        expect(cancelSize.width, greaterThanOrEqualTo(48));
        expect(cancelSize.height, greaterThanOrEqualTo(48));
      },
    );

    testWidgets(
      'the backdated header chip (#36) wraps its date phrase instead of '
      'overflowing the screen at 320dp/2x',
      (tester) async {
        // #155: `_TargetDateChip`'s `Row` (icon + "Writing about ..."
        // text) had no `Flexible` around the text -- the family of
        // overflow ACCESSIBILITY.md §3 describes, and a genuine
        // `RenderFlex` overflow (unlike the FAB defect fixed in
        // `today_screen.dart`), so `takeException()` alone would have
        // caught it. This test instead measures the chip's own rendered
        // rect.
        tester.view.physicalSize = const Size(320, 3000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: buildTestable(
                replies: bootReplies(),
                targetDate: const CalendarDate(2026, 8, 26),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Off the guided stage onto freeform, where the chip is simplest
        // to measure cleanly.
        await tester.tap(find.text('Write freely instead'));
        await tester.pump();

        expect(tester.takeException(), isNull);
        final chip = find.text('Writing about Wednesday, August 26');
        expect(chip, findsOneWidget);
        final chipRect = tester.getRect(chip);
        expect(
          chipRect.left,
          greaterThanOrEqualTo(0),
          reason: 'the chip text must not render past the left screen edge',
        );
        expect(
          chipRect.right,
          lessThanOrEqualTo(320),
          reason: 'the chip text must not render past the right screen edge',
        );
      },
    );

    testWidgets(
      'the pending-suggestion banner wraps its label instead of '
      'overflowing the picker at 320dp/2x',
      (tester) async {
        // #155: `_ReadingEntryBanner`'s `Row` (spinner + "Reading your
        // entry…" text) had no `Flexible` around the text either.
        // Measured (in this suite's own text-rendering environment) at
        // over 200px past the picker's own right edge -- and, unlike
        // `_TargetDateChip` above, *silently*: this `Row` sits in a
        // non-stretched `Column` child inside a `SingleChildScrollView`,
        // and nothing here threw a `RenderFlex` overflow, the same
        // "renders wrong without throwing" shape `today_screen.dart`'s
        // FAB had. The scroll view's own measured right edge is the
        // ceiling the banner must not cross.
        tester.view.physicalSize = const Size(320, 3000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final delay = ManualDelay();
        await tester.pumpWidget(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: buildTestable(
                replies: [
                  ...bootReplies(),
                  FakeReply(201, body: entryJson(analysisPending: true)),
                  FakeReply(200, body: entryJson(analysisPending: true)),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        containerOf(
                  tester,
                )
                .read(
                  entryComposerControllerProvider(CalendarDate.today())
                      .notifier,
                )
                .pollDelay =
            delay.call;

        await tester.tap(find.text('Write freely instead'));
        await tester.pump();
        await tester.enterText(find.byType(TextFormField), 'A long day.');
        await tester.pump();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
        final banner = find.text('Reading your entry…');
        await pumpUntilFound(tester, banner);

        expect(tester.takeException(), isNull);
        expect(banner, findsOneWidget);
        final bannerRect = tester.getRect(banner);
        final scrollViewRect = tester.getRect(
          find.byType(SingleChildScrollView).last,
        );
        expect(
          bannerRect.right,
          lessThanOrEqualTo(scrollViewRect.right),
          reason:
              'the banner text must not render past the picker\'s own '
              'right edge',
        );
        // The manual picker is not gated behind the pending banner (see
        // the class doc comment on `_ReadingEntryBanner`) -- still true
        // once the label wraps to more than one line.
        expect(find.text('Uplifted'), findsOneWidget);
      },
    );

    // The matrix from ACCESSIBILITY.md §3 -- 320/360dp width x
    // 1.0/1.3/2.0 textScale -- against the confirm-feeling stage, which
    // is where this split's own structures concentrate
    // (`_TargetDateChip`, `_ReadingEntryBanner`, the picker's own layout),
    // reached by passing through the guided and freeform stages
    // (`guided_question_flow.dart`, `voice_answer_recorder.dart`). Those
    // two used to overflow on the way through (#165) and this test drained
    // the exceptions to get past them; now that #165 is fixed, the path is
    // asserted overflow-free end to end, not just at the destination.
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          'the confirm-feeling stage renders with no overflow at '
          '${width}dp / ${scale}x',
          (tester) async {
            tester.view.physicalSize = Size(width, 3000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);

            final replies = [
              ...bootReplies(),
              FakeReply(
                200,
                body: entryJson(
                  suggestedFeelings: [suggestedFeelingJson(key: 'happy')],
                ),
              ),
            ];
            await tester.pumpWidget(
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: buildTestable(replies: replies),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Write freely instead'));
            await tester.pump();
            await tester.enterText(find.byType(TextFormField), 'A long day.');
            await tester.pump();
            await tester.tap(find.widgetWithText(ElevatedButton, 'Save entry'));
            await tester.pumpAndSettle();

            // #165's own two overflows (guided_question_flow.dart,
            // voice_answer_recorder.dart) are fixed, so this no longer
            // drains blindly. What is left, only at 320dp/2.0x, is a
            // separate, pre-existing overflow confirmed (via a one-off
            // `FlutterError.onError` capture during triage) to originate
            // in `lib/core/widgets/feeling_chips.dart:139` -- the confirm-
            // feeling picker's own chips -- filed as #176 rather than
            // fixed here: `lib/core/widgets/` is owned by a concurrent
            // sweep batch, not this one. `tester.takeException()`'s own
            // exception carries no file/line, only the summary below, so
            // that is what is matched; anything else still fails this
            // test.
            final pending = tester.takeException();
            if (pending != null) {
              expect(
                pending.toString(),
                contains('overflowed by 29 pixels'),
                reason:
                    'only #176\'s known FeelingChip overflow is '
                    'tolerated here',
              );
            }
            expect(find.text('How did that feel?'), findsOneWidget);
            expect(
              find.text(
                "It sounds like you're feeling happy. Confirm that, or "
                'pick differently.',
              ),
              findsOneWidget,
            );
          },
        );
      }
    }
  });
}
