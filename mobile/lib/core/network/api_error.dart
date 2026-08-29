/// Everything that can go wrong when talking to the backend.
///
/// Sealed so a screen switching over a failure handles every case the client
/// can produce, and the compiler says so when a new one is added:
///
/// ```dart
/// final message = switch (error) {
///   BackendNotConfigured() => 'Set your server address in Settings.',
///   NetworkFailure() => 'Could not reach the server.',
///   Unauthorized() => 'Please sign in again.',
///   HttpFailure(:final statusCode) => 'Server error ($statusCode).',
/// };
/// ```
sealed class const ApiError(final String message) implements Exception {
  /// The HTTP status behind this failure, or `null` if it never reached HTTP.
  int? get statusCode => null;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when a request is attempted before a server address has been set.
///
/// The only failure the user can fix without leaving the app, so screens should
/// offer a route to Settings rather than only showing the message.
final class const BackendNotConfigured() extends ApiError {
  this : super('No server address configured');
}

/// Thrown when the request never got an HTTP response: DNS, timeout, refused
/// connection, or TLS failure.
final class const NetworkFailure(super.message) extends ApiError;

/// Thrown on HTTP 401, meaning the session is missing or has expired.
final class const Unauthorized([
  super.message = 'Your session has expired',
]) extends ApiError {
  @override
  int get statusCode => 401;
}

/// Thrown for any other non-success HTTP status.
///
/// [body] is the decoded response body, kept because some failures carry more
/// than a sentence: the diary backend answers a stale edit with `409` and the
/// entry as actually stored, which is what lets the conflict screen show both
/// versions without a second round trip.
final class const HttpFailure(
  super.message,
  final int status, [
  final Object? body,
]) extends ApiError {
  @override
  int get statusCode => status;
}
