import '../config/app_config.dart';
import '../network/api_client.dart';
import '../network/api_error.dart';
import 'transcription.dart';

/// Talks to the transcription endpoints and drives the poll loop.
///
/// The upload is a raw audio body rather than a multipart form: the backend
/// registers a raw body parser for audio content types and reads the
/// request body as a buffer, so a multipart envelope would arrive as bytes
/// it does not know how to unwrap — [ApiClient.postBytes] exists for
/// exactly this.
class TranscriptionsApi {
  /// Creates an API over an [ApiClient].
  TranscriptionsApi(this._client);

  static const Duration _defaultPollInterval = Duration(seconds: 1);
  static const Duration _defaultTimeout = Duration(minutes: 10);

  final ApiClient _client;

  /// Uploads [audio] under [contentType] and returns the id of the job
  /// started to transcribe it.
  Future<String> start(List<int> audio, String contentType) =>
      _client.postBytes(
        AppConfig.transcriptionsPath,
        (json) => json['id']! as String,
        bytes: audio,
        contentType: contentType,
      );

  /// Reads the current state of transcription job [jobId].
  Future<TranscriptionJob> poll(String jobId) => _client.getObject(
    AppConfig.transcriptionPath(jobId),
    (json) => TranscriptionJob(
      TranscriptionStatus.fromWire(json['status'] as String?),
      transcript: json['transcript'] as String?,
      error: json['error'] as String?,
    ),
  );

  /// Uploads [audio] and waits for its transcript.
  ///
  /// Transcription is asynchronous on purpose — whisper.cpp can take a
  /// while on a long answer, and the backend hands back a job id
  /// immediately rather than holding an HTTP request open through a
  /// reverse proxy's idle timeout. So this polls, exactly as the web client
  /// does, with the same one-second interval and the same generous
  /// ceiling: a slow transcription is normal, a silent hang is not.
  ///
  /// [delay] is injectable so a test can drive this without a real clock —
  /// pass a no-op to keep the suite instant.
  Future<String> transcribe(
    List<int> audio,
    String contentType, {
    Duration pollInterval = _defaultPollInterval,
    Duration timeout = _defaultTimeout,
    Future<void> Function(Duration) delay = Future.delayed,
  }) async {
    final jobId = await start(audio, contentType);

    var waited = Duration.zero;
    while (waited < timeout) {
      await delay(pollInterval);
      waited += pollInterval;

      final job = await poll(jobId);
      switch (job.status) {
        case TranscriptionStatus.completed:
          return job.transcript ?? '';
        case TranscriptionStatus.failed:
          throw NetworkFailure(
            job.error ?? 'The recording could not be transcribed.',
          );
        case TranscriptionStatus.pending:
        // Keep waiting.
      }
    }

    throw const NetworkFailure('Transcription is taking longer than expected.');
  }
}
