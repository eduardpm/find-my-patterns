import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'audio_recorder_plugin.dart';

/// Thrown by [DiaryAudioRecorder.start] when a recording could not begin.
sealed class const DiaryRecordingFailure() implements Exception;

/// The user, or the platform, refused microphone access.
final class const MicrophonePermissionDenied() extends DiaryRecordingFailure;

/// The microphone could not be started for a reason other than a refused
/// permission.
final class const MicrophoneUnavailable() extends DiaryRecordingFailure;

/// Records a spoken diary answer to a file in the app's cache directory.
///
/// Recordings live in the cache directory, never in shared storage: a
/// half-finished diary answer is as private as the entry it becomes, and
/// the caller deletes the file as soon as it has been uploaded (see
/// `VoiceAnswerRecorder`).
///
/// AAC in an MP4 container at 44100 Hz / 96 kbps — see
/// [DefaultAudioRecorderPlugin] for why. [contentType] is what an upload
/// should send as `Content-Type`; the backend pipes whatever arrives
/// through ffmpeg regardless of the exact codec.
class DiaryAudioRecorder {
  /// Creates a recorder over [plugin] (the real device microphone by
  /// default) and [cacheDirectory] (the real cache directory by default).
  ///
  /// Both are injectable seams: [plugin] so a test never touches a
  /// platform channel, and [cacheDirectory] so a test never writes into the
  /// real device cache.
  DiaryAudioRecorder({
    AudioRecorderPlugin? plugin,
    this.cacheDirectory = getTemporaryDirectory,
  }) : _plugin = plugin ?? DefaultAudioRecorderPlugin();

  /// The MIME type of what [stop] produces, for the upload's `Content-Type`.
  static const String contentType = 'audio/mp4';

  /// Resolves the directory recordings are written into. The real cache
  /// directory by default; a test points this at a temp directory instead.
  final Future<Directory> Function() cacheDirectory;

  final AudioRecorderPlugin _plugin;

  String? _activePath;

  /// Whether a recording is currently in progress.
  bool get isRecording => _activePath != null;

  /// Begins recording. A no-op if a recording is already in progress.
  ///
  /// Throws [MicrophonePermissionDenied] when the microphone permission was
  /// refused, or [MicrophoneUnavailable] when the microphone could not be
  /// started for any other reason (already in use, encoder unavailable,
  /// …).
  Future<void> start() async {
    if (_activePath != null) return;

    final granted = await _plugin.hasPermission();
    if (!granted) throw const MicrophonePermissionDenied();

    final directory = await cacheDirectory();
    final path =
        '${directory.path}/answer-${DateTime.now().microsecondsSinceEpoch}.m4a';
    try {
      await _plugin.start(path);
    } on Exception {
      throw const MicrophoneUnavailable();
    }
    _activePath = path;
  }

  /// Stops recording and returns the file, or `null` when nothing usable
  /// was captured.
  ///
  /// A recording stopped almost immediately produces no valid container —
  /// treated as "no recording" rather than as an error, so a mis-tap on the
  /// record button never surfaces as a failed-transcription message.
  Future<File?> stop() async {
    if (_activePath == null) return null;
    _activePath = null;

    String? resultPath;
    try {
      resultPath = await _plugin.stop();
    } on Exception {
      resultPath = null;
    }
    if (resultPath == null) return null;

    final file = File(resultPath);
    if (!file.existsSync()) return null;
    if (file.lengthSync() <= 0) {
      await _safeDelete(file);
      return null;
    }
    return file;
  }

  /// Abandons any in-progress recording and deletes its file.
  Future<void> cancel() async {
    if (_activePath == null) return;
    _activePath = null;
    try {
      await _plugin.cancel();
    } on Exception {
      // Nothing usable was written either way.
    }
  }

  Future<void> _safeDelete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Best effort: no upload happened, so nothing depends on this file
      // actually going away.
    }
  }
}
