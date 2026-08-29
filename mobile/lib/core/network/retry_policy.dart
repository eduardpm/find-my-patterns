import 'api_error.dart';

/// How long to wait before rebuilding a provider whose build failed, or `null`
/// to stop retrying and surface the failure.
///
/// Riverpod's own default retries anything that is not an [Error] up to ten
/// times, doubling the delay to a 6.4-second cap — about forty seconds in all.
/// Every failure this app raises is an [ApiError], which is an `Exception`, so
/// that default applies to all of them: a mistyped server address would leave a
/// screen spinning for forty seconds before saying anything, having asked the
/// unreachable host eleven times on the way.
///
/// So only a failure that might genuinely resolve itself on its own is retried,
/// and only twice:
///
/// * [NetworkFailure] — a dropped connection or a timeout, which the next
///   attempt may well get through.
/// * [HttpFailure] with a 5xx status — the server's fault, and servers recover.
///
/// Everything else is a fact that will not change by asking again.
/// [BackendNotConfigured] needs the user to type an address, [Unauthorized]
/// needs them to sign in, and a 4xx is the request itself being wrong. Those
/// surface immediately, which is what lets the screen say something true while
/// the person is still looking at it.
Duration? apiRetryPolicy(int retryCount, Object error) {
  if (retryCount >= _maxRetries) return null;
  final worthRetrying = switch (error) {
    NetworkFailure() => true,
    HttpFailure(:final statusCode) => statusCode >= 500,
    _ => false,
  };
  if (!worthRetrying) return null;
  return Duration(milliseconds: _baseDelayMs * (retryCount + 1));
}

/// Two attempts after the first: enough to ride out a blip, few enough that a
/// genuinely unreachable server is reported in well under a second.
const int _maxRetries = 2;

/// The first backoff step; the second wait is twice this.
const int _baseDelayMs = 200;
