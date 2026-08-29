/// @docImport 'diary_audio_recorder.dart';
library;

import 'package:record/record.dart' as record;

/// The slice of the `record` package's surface [DiaryAudioRecorder] actually
/// calls.
///
/// `record`'s own [record.AudioRecorder] is a concrete class that talks to a
/// platform channel on every method. Faking that whole shape in a test would
/// mean standing up a fake platform channel for a surface the domain layer
/// never touches directly. This interface names only what is actually
/// called, so a test double stays a handful of methods instead of a plugin
/// — the same pattern `lib/core/notifications/notifications_plugin.dart`
/// uses for `flutter_local_notifications`.
abstract interface class AudioRecorderPlugin {
  /// Checks (and, per the `record` package's own contract, requests) the
  /// microphone permission.
  Future<bool> hasPermission();

  /// Begins recording to [path].
  Future<void> start(String path);

  /// Stops the current recording and returns the file path that was
  /// written, or `null` if there is nothing to report.
  Future<String?> stop();

  /// Stops and discards whatever has been recorded so far.
  Future<void> cancel();

  /// Releases the resources this plugin holds.
  Future<void> dispose();
}

/// The real [AudioRecorderPlugin], backed by the `record` package.
///
/// AAC in an MP4 container, 44100 Hz, 96 kbps — the same encoding the
/// Kotlin original chose. The backend does not care about the exact codec:
/// it pipes whatever arrives through ffmpeg to the 16 kHz mono WAV
/// whisper.cpp wants, so the job here is only to produce something ffmpeg
/// can decode at a sample rate that does not throw away speech detail. A
/// too-low rate cannot be recovered from later.
class DefaultAudioRecorderPlugin implements AudioRecorderPlugin {
  /// Creates a plugin over a fresh `record` package recorder.
  DefaultAudioRecorderPlugin() : _recorder = record.AudioRecorder();

  static const record.RecordConfig _config = record.RecordConfig(
    encoder: record.AudioEncoder.aacLc,
    sampleRate: 44100,
    bitRate: 96000,
    numChannels: 1,
  );

  final record.AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(_config, path: path);

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}
