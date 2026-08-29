import 'dart:io';

import 'package:find_my_patterns/core/audio/diary_audio_recorder.dart';
import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/compose/voice_answer_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/audio/fake_audio_recorder_plugin.dart';
import '../../support/fake_http.dart';
import '../../support/harness.dart';

void main() {
  late Directory tempDir;
  late FakeAudioRecorderPlugin plugin;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('voice-recorder-test-');
    plugin = FakeAudioRecorderPlugin();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Writes a captured recording under [tempDir] and points the fake
  /// plugin's next `stop()` at it.
  ///
  /// Synchronous on purpose: `flutter_test`'s fake-async zone never lets a
  /// *real* asynchronous `dart:io` call complete on its own (nothing ever
  /// drives its underlying real timer forward outside `runAsync`), so test
  /// setup that only needs to put bytes on disk uses the `*Sync` file APIs
  /// rather than fighting that zone for something this incidental.
  File writeCapturedFile({int bytes = 4}) {
    final file = File('${tempDir.path}/captured.m4a');
    file.writeAsBytesSync(List.filled(bytes, 1));
    plugin.nextStopPath = file.path;
    return file;
  }

  Widget buildTestable({
    required ValueChanged<String> onTranscript,
    ValueChanged<bool>? onBusyChange,
    FakeHttpAdapter? adapter,
  }) {
    final recorder = DiaryAudioRecorder(
      plugin: plugin,
      cacheDirectory: () async => tempDir,
    );
    final harness = Harness(
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
      adapter:
          adapter ?? FakeHttpAdapter.always(const FakeReply(200, body: {})),
    );
    return ProviderScope(
      overrides: [
        requireAuthProvider.overrideWithValue(harness.requireAuth),
        settingsStoreProvider.overrideWithValue(harness.store),
        apiClientProvider.overrideWithValue(harness.client),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: VoiceAnswerRecorder(
            onTranscript: onTranscript,
            onBusyChange: onBusyChange ?? (_) {},
            recorder: recorder,
            transcriptionDelay: (_) async {},
          ),
        ),
      ),
    );
  }

  /// Taps "Stop recording" and lets the real file read + (fake-HTTP-backed)
  /// transcription chain behind it actually run to completion.
  ///
  /// The tap itself must happen *inside* `runAsync`: an async callback's
  /// zone is fixed at the moment it starts running, not at some later
  /// `await`, so starting the tap from the ordinary (fake-async) test body
  /// would leave the widget's own `file.readAsBytes()` permanently stuck --
  /// entering `runAsync` afterwards cannot rescue a chain that already
  /// began in the wrong zone.
  Future<void> stopRecordingAndSettle(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Stop recording'));
    });
    // Stopping kicks off real file I/O and two round trips through the fake
    // adapter, and how long that takes depends on what else the machine is
    // doing. A fixed sleep here is a race — it passed alone and failed with an
    // emulator and a Gradle build running beside it. So wait for the outcome
    // rather than for a duration: pump between short real delays until the
    // recorder is back at rest, bounded so a genuine hang still fails.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
      if (find.text('Speak instead').evaluate().isNotEmpty) return;
    }
    fail('The recorder never returned to idle.');
  }

  group('idle state', () {
    testWidgets('shows "Speak instead"', (tester) async {
      await tester.pumpWidget(buildTestable(onTranscript: (_) {}));
      expect(find.text('Speak instead'), findsOneWidget);
    });
  });

  group('recording', () {
    testWidgets('tapping the idle button starts recording and shows '
        '"Stop recording"', (tester) async {
      await tester.pumpWidget(buildTestable(onTranscript: (_) {}));
      await tester.tap(find.text('Speak instead'));
      await tester.pump();
      expect(find.text('Stop recording'), findsOneWidget);
    });

    testWidgets('reports busy while recording', (tester) async {
      final busyValues = <bool>[];
      await tester.pumpWidget(
        buildTestable(onTranscript: (_) {}, onBusyChange: busyValues.add),
      );
      await tester.tap(find.text('Speak instead'));
      await tester.pump();
      expect(busyValues, contains(true));
    });

    testWidgets('announces "Recording." while recording', (tester) async {
      await tester.pumpWidget(buildTestable(onTranscript: (_) {}));
      await tester.tap(find.text('Speak instead'));
      await tester.pump();
      expect(find.text('Recording.'), findsOneWidget);
    });
  });

  group('transcribing', () {
    testWidgets('stopping shows "Transcribing…" and disables the button', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestable(onTranscript: (_) {}));
      await tester.tap(find.text('Speak instead'));
      await tester.pump();
      writeCapturedFile();

      // Deliberately *not* run through `runAsync`/settled: the phase flips
      // to "transcribing" synchronously, before the widget's own real file
      // read ever starts, so this state is observable with a plain tap and
      // pump. (The chain behind it never gets to finish in this test --
      // see `stopRecordingAndSettle` for the completion path.)
      await tester.tap(find.text('Stop recording'));
      await tester.pump();

      expect(find.text('Transcribing…'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('delivers the transcript and returns to idle once done', (
      tester,
    ) async {
      String? transcript;
      final busyValues = <bool>[];
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: {'id': 'job-1'}),
        FakeReply(
          200,
          body: {'status': 'completed', 'transcript': 'hello there'},
        ),
      ]);
      await tester.pumpWidget(
        buildTestable(
          onTranscript: (t) => transcript = t,
          onBusyChange: busyValues.add,
          adapter: adapter,
        ),
      );
      await tester.tap(find.text('Speak instead'));
      await tester.pump();
      writeCapturedFile();

      await stopRecordingAndSettle(tester);

      expect(transcript, 'hello there');
      expect(find.text('Speak instead'), findsOneWidget);
      expect(busyValues.last, isFalse);
    });
  });

  group('errors', () {
    testWidgets('a permission refusal shows the permission message', (
      tester,
    ) async {
      plugin.permissionGranted = false;
      await tester.pumpWidget(buildTestable(onTranscript: (_) {}));

      await tester.tap(find.text('Speak instead'));
      await tester.pump();

      expect(
        find.text('Microphone access is needed to record an answer.'),
        findsOneWidget,
      );
    });

    testWidgets('a microphone failure shows the unavailable message', (
      tester,
    ) async {
      plugin.nextStartError = Exception('boom');
      await tester.pumpWidget(buildTestable(onTranscript: (_) {}));

      await tester.tap(find.text('Speak instead'));
      await tester.pump();

      expect(
        find.text('The microphone could not be started.'),
        findsOneWidget,
      );
    });

    testWidgets('stopping an empty recording shows a too-short message', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestable(onTranscript: (_) {}));
      await tester.tap(find.text('Speak instead'));
      await tester.pump();
      // Nothing usable captured: the fake plugin's next stop path is null,
      // so `DiaryAudioRecorder.stop()` returns before touching any file --
      // a plain tap/pump is enough, no real IO is ever involved.
      await tester.tap(find.text('Stop recording'));
      await tester.pump();

      expect(find.text('That recording was too short.'), findsOneWidget);
      expect(find.text('Speak instead'), findsOneWidget);
    });

    testWidgets('an empty transcript shows a nothing-heard message', (
      tester,
    ) async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: {'id': 'job-1'}),
        FakeReply(200, body: {'status': 'completed', 'transcript': '   '}),
      ]);
      await tester.pumpWidget(
        buildTestable(onTranscript: (_) {}, adapter: adapter),
      );
      await tester.tap(find.text('Speak instead'));
      await tester.pump();
      writeCapturedFile();

      await stopRecordingAndSettle(tester);

      expect(
        find.text('Nothing could be heard in that recording.'),
        findsOneWidget,
      );
    });

    testWidgets('a transcription failure shows the ApiError message', (
      tester,
    ) async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: {'id': 'job-1'}),
        FakeReply(200, body: {'status': 'failed', 'error': 'model crashed'}),
      ]);
      await tester.pumpWidget(
        buildTestable(onTranscript: (_) {}, adapter: adapter),
      );
      await tester.tap(find.text('Speak instead'));
      await tester.pump();
      writeCapturedFile();

      await stopRecordingAndSettle(tester);

      expect(find.text('model crashed'), findsOneWidget);
    });

    testWidgets('starting a new recording clears a previous error', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestable(onTranscript: (_) {}));
      await tester.tap(find.text('Speak instead'));
      await tester.pump();
      await tester.tap(find.text('Stop recording'));
      await tester.pump();
      expect(find.text('That recording was too short.'), findsOneWidget);

      await tester.tap(find.text('Speak instead'));
      await tester.pump();

      expect(find.text('That recording was too short.'), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('the status message is announced through a live region', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(buildTestable(onTranscript: (_) {}));
      await tester.tap(find.text('Speak instead'));
      await tester.pump();

      final node = tester.getSemantics(find.text('Recording.'));
      expect(node.label, 'Recording.');
      handle.dispose();
    });
  });

  group('disposal', () {
    testWidgets('leaving the screen mid-recording cancels the recording', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestable(onTranscript: (_) {}));
      await tester.tap(find.text('Speak instead'));
      await tester.pump();
      expect(plugin.startedPaths, hasLength(1));

      await tester.pumpWidget(const SizedBox());

      expect(plugin.cancelCallCount, 1);
    });
  });
}
