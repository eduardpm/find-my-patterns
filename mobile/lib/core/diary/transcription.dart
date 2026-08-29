/// The state of an asynchronous transcription job.
enum TranscriptionStatus {
  /// Still running; poll again.
  pending,

  /// Finished; [TranscriptionJob.transcript] holds the result.
  completed,

  /// Finished with an error; [TranscriptionJob.error] explains why.
  failed;

  /// Resolves a wire status string; anything unrecognised, including null,
  /// falls back to [pending] rather than throwing — a status this build
  /// does not know about is safest read as "keep waiting".
  static TranscriptionStatus fromWire(String? raw) => switch (raw) {
    'completed' => TranscriptionStatus.completed,
    'failed' => TranscriptionStatus.failed,
    _ => TranscriptionStatus.pending,
  };
}

/// One shape covers all three states because that is how the backend serves
/// them: [status] discriminates, and [transcript] and [error] are present
/// only for the state they belong to.
class const TranscriptionJob(
  final TranscriptionStatus status, {
  final String? transcript,
  final String? error,
});
