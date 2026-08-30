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

/// Whether [error] is the backend's `402 premium_required` (M-3, #48):
/// `POST /experiments` and `GET /insights/digest` answer this literal body,
/// `{"error": "premium_required"}`, when the caller's tier does not cover
/// the feature (`backend/tests/contract/free-paid-boundary.test.ts`).
///
/// A predicate over [HttpFailure] rather than a new sealed [ApiError] case.
/// [Unauthorized] earns its own case because *every* request can answer
/// 401, so every exhaustive `switch (error)` in this app already has to
/// decide what a 401 means. `premium_required` is nothing like that: it
/// only ever comes back from the two calls above, so giving it a sealed
/// variant would force the switches in `day_entries_controller.dart`,
/// `entry_detail_controller.dart`, `experiment_results_screen.dart`,
/// `mood_trend_chart.dart`, `insights_screen.dart` and
/// `topics_controller.dart` -- none of which ever call a gated endpoint --
/// to each grow a branch that can structurally never run there. One
/// predicate, checked at the two call sites that actually need it
/// (`experiment_setup_sheet.dart`, `app.dart`'s digest-tap handler), says
/// the same thing without that cost.
bool isPremiumRequired(ApiError error) =>
    error is HttpFailure &&
    error.statusCode == 402 &&
    switch (error.body) {
      {'error': 'premium_required'} => true,
      _ => false,
    };
