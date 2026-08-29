import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One canned HTTP reply.
class FakeReply {
  /// Creates a reply with [statusCode] and an optional JSON [body].
  const FakeReply(this.statusCode, {this.body, this.headers})
    : rawBody = null,
      throwsNetworkError = false;

  /// Creates a reply whose body is sent exactly as [rawBody] rather than
  /// JSON-encoded — for an endpoint that answers a file instead of JSON, the
  /// diary export (`GET /export`) being the only one today.
  const FakeReply.raw(this.statusCode, this.rawBody, {this.headers})
    : body = null,
      throwsNetworkError = false;

  /// Creates a reply that fails at the transport layer instead of returning.
  const FakeReply.networkError()
    : statusCode = 0,
      body = null,
      rawBody = null,
      headers = null,
      throwsNetworkError = true;

  /// The HTTP status to report.
  final int statusCode;

  /// The JSON body to encode, or `null` for an empty body.
  final Object? body;

  /// The body to send verbatim, bypassing JSON encoding. Set by
  /// [FakeReply.raw]; `null` for every other constructor.
  final String? rawBody;

  /// Response headers, beyond the `Content-Type` this adapter always sends.
  final Map<String, List<String>>? headers;

  /// Whether this reply should surface as a connection failure.
  final bool throwsNetworkError;
}

/// A [HttpClientAdapter] that answers from a script instead of the network.
///
/// Keeps `ApiClient` tests entirely offline while still exercising the real Dio
/// pipeline: interceptors, the cookie manager, and status handling all run.
class FakeHttpAdapter implements HttpClientAdapter {
  /// Creates an adapter that replies with [replies], in order.
  FakeHttpAdapter(this.replies);

  /// Creates an adapter that answers every request with [reply].
  FakeHttpAdapter.always(FakeReply reply) : replies = [reply], _repeat = true;

  /// The scripted replies.
  final List<FakeReply> replies;

  bool _repeat = false;
  int _index = 0;

  /// Every request the adapter has been asked to send, in order.
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = _repeat ? replies.first : replies[_index++];
    if (reply.throwsNetworkError) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'fake connection refused',
      );
    }
    final encoded =
        reply.rawBody ?? (reply.body == null ? '' : jsonEncode(reply.body));
    return ResponseBody.fromString(
      encoded,
      reply.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...?reply.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
