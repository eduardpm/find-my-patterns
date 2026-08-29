import 'dart:async';
import 'dart:io';

import 'package:find_my_patterns/core/audio/diary_audio_recorder.dart';
import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/compose/entry_composer_controller.dart';
import 'package:find_my_patterns/features/compose/entry_composer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/audio/fake_audio_recorder_plugin.dart';
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
  }) {
    final harness = Harness(
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
      adapter: FakeHttpAdapter(replies),
    );
    return ProviderScope(
      overrides: [
        requireAuthProvider.overrideWithValue(harness.requireAuth),
        settingsStoreProvider.overrideWithValue(harness.store),
        apiClientProvider.overrideWithValue(harness.client),
      ],
      child: MaterialApp(
        home: EntryComposerScreen(
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

      await tester.tap(find.byIcon(Icons.close));
      expect(cancelled, isTrue);
    });
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
        ).read(entryComposerControllerProvider.notifier).pollDelay = delay.call;

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
        ).read(entryComposerControllerProvider.notifier).pollDelay = delay.call;

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
        ).read(entryComposerControllerProvider.notifier).pollDelay = delay.call;

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
}
