import 'dart:io';

import 'package:find_my_patterns/core/audio/diary_audio_recorder.dart';
import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/compose/entry_composer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/audio/fake_audio_recorder_plugin.dart';
import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

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
