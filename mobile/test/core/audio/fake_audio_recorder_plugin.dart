/// @docImport 'package:find_my_patterns/core/audio/diary_audio_recorder.dart';
library;

import 'package:find_my_patterns/core/audio/audio_recorder_plugin.dart';

/// An in-memory [AudioRecorderPlugin] double.
///
/// Records every call so a test can assert on what [DiaryAudioRecorder]
/// asked for, and lets a test script permission refusals, start failures,
/// and what [stop] hands back — all without touching a real platform
/// channel.
class FakeAudioRecorderPlugin implements AudioRecorderPlugin {
  /// Answered by [hasPermission].
  bool permissionGranted = true;

  /// Thrown by [start] when set, standing in for the microphone failing to
  /// open.
  Exception? nextStartError;

  /// Answered by [stop]. `null` mirrors "nothing usable was captured".
  String? nextStopPath;

  /// Every path [start] was called with, in order.
  final List<String> startedPaths = [];

  /// Incremented on every [cancel] call.
  int cancelCallCount = 0;

  /// Incremented on every [dispose] call.
  int disposeCallCount = 0;

  /// Whether [cancel] has been called more recently than [start].
  bool _cancelled = false;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<void> start(String path) async {
    if (nextStartError case final error?) {
      nextStartError = null;
      throw error;
    }
    _cancelled = false;
    startedPaths.add(path);
  }

  @override
  Future<String?> stop() async => _cancelled ? null : nextStopPath;

  @override
  Future<void> cancel() async {
    cancelCallCount++;
    _cancelled = true;
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
  }
}
