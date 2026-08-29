import 'dart:io';

import 'package:find_my_patterns/core/audio/diary_audio_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_audio_recorder_plugin.dart';

void main() {
  late Directory tempDir;
  late FakeAudioRecorderPlugin plugin;
  late DiaryAudioRecorder recorder;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diary-audio-test-');
    plugin = FakeAudioRecorderPlugin();
    recorder = DiaryAudioRecorder(
      plugin: plugin,
      cacheDirectory: () async => tempDir,
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Writes a file with [bytes] worth of content under [tempDir] and points
  /// the fake plugin's next `stop()` at it.
  Future<File> writeCapturedFile({int bytes = 4}) async {
    final file = File('${tempDir.path}/captured.m4a');
    await file.writeAsBytes(List.filled(bytes, 1));
    plugin.nextStopPath = file.path;
    return file;
  }

  group('contentType', () {
    test('is the MP4/AAC MIME type the backend expects', () {
      expect(DiaryAudioRecorder.contentType, 'audio/mp4');
    });
  });

  group('start', () {
    test(
      'throws MicrophonePermissionDenied when permission is refused',
      () async {
        plugin.permissionGranted = false;
        await expectLater(
          recorder.start(),
          throwsA(isA<MicrophonePermissionDenied>()),
        );
        expect(plugin.startedPaths, isEmpty);
      },
    );

    test(
      'throws MicrophoneUnavailable when the plugin fails to start',
      () async {
        plugin.nextStartError = Exception('boom');
        await expectLater(
          recorder.start(),
          throwsA(isA<MicrophoneUnavailable>()),
        );
      },
    );

    test('writes into the injected cache directory', () async {
      await recorder.start();
      expect(plugin.startedPaths, hasLength(1));
      expect(plugin.startedPaths.single, startsWith(tempDir.path));
    });

    test('is a no-op when a recording is already in progress', () async {
      await recorder.start();
      await recorder.start();
      expect(plugin.startedPaths, hasLength(1));
    });

    test('marks the recorder as recording', () async {
      expect(recorder.isRecording, isFalse);
      await recorder.start();
      expect(recorder.isRecording, isTrue);
    });
  });

  group('stop', () {
    test('returns null when nothing was ever started', () async {
      expect(await recorder.stop(), isNull);
    });

    test('returns null when the plugin reports nothing usable', () async {
      await recorder.start();
      plugin.nextStopPath = null;
      expect(await recorder.stop(), isNull);
    });

    test(
      'returns null for a recording stopped almost immediately -- a '
      'mis-tap must not read as a failure',
      () async {
        await recorder.start();
        await writeCapturedFile(bytes: 0);
        expect(await recorder.stop(), isNull);
      },
    );

    test('returns the file when something usable was captured', () async {
      await recorder.start();
      final file = await writeCapturedFile();
      final result = await recorder.stop();
      expect(result?.path, file.path);
    });

    test(
      'clears the recording state so a second stop reports nothing',
      () async {
        await recorder.start();
        await writeCapturedFile();
        await recorder.stop();
        expect(recorder.isRecording, isFalse);
        expect(await recorder.stop(), isNull);
      },
    );
  });

  group('cancel', () {
    test('delegates to the plugin and clears the recording state', () async {
      await recorder.start();
      await recorder.cancel();
      expect(plugin.cancelCallCount, 1);
      expect(recorder.isRecording, isFalse);
    });

    test('is a no-op when nothing is recording', () async {
      await recorder.cancel();
      expect(plugin.cancelCallCount, 0);
    });

    test('a cancelled recording reports nothing on a later stop', () async {
      await recorder.start();
      await recorder.cancel();
      expect(await recorder.stop(), isNull);
    });
  });
}
