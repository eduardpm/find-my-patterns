import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../config/app_config.dart';
import '../settings/settings.dart';
import 'api_error.dart';

/// A decoded JSON object, as the backend sends them.
typedef JsonObject = Map<String, Object?>;

/// Converts one JSON object from the backend into a model.
typedef JsonDecoder<T> = T Function(JsonObject json);

/// The shared HTTP core: every request an app makes goes through one of these.
///
/// Three decisions carried over from the apps this base was extracted from:
///
/// * The server address is user-entered and can change at any moment, so a
///   request interceptor rewrites the base URL on every outgoing request rather
///   than the client being rebuilt when the address changes.
/// * Sessions ride on HttpOnly cookies held in the injected [CookieJar]. The
///   app supplies a `PersistCookieJar` so a session survives a restart; tests
///   supply an in-memory one.
/// * Failures surface as [ApiError]s, which are sealed, so a caller cannot
///   forget to handle one.
///
/// Every read method takes a [JsonDecoder] and returns a real model type. The
/// client deliberately never hands back `dynamic`: with strict casts enabled
/// that would push an unchecked cast into every call site.
class ApiClient {
  /// Creates a client, optionally over a caller-supplied [dio] and [cookieJar].
  ///
  /// Both are injectable so tests can drive the client through a fake adapter
  /// without touching the network.
  ApiClient({Dio? dio, CookieJar? cookieJar})
    : cookieJar = cookieJar ?? CookieJar(),
      _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 10),
      headers: const {'Accept': 'application/json'},
      // Non-2xx statuses are turned into ApiErrors in [_send] instead of
      // DioExceptions, so callers see one failure type.
      validateStatus: (_) => true,
    );
    _dio.interceptors.add(CookieManager(this.cookieJar));
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (!_backend.isConfigured) {
            handler.reject(
              DioException(
                requestOptions: options,
                error: const BackendNotConfigured(),
              ),
            );
            return;
          }
          options.baseUrl = _backend.origin;
          handler.next(options);
        },
      ),
    );
  }

  /// The jar holding the session cookie.
  final CookieJar cookieJar;

  final Dio _dio;

  BackendAddress _backend = BackendAddress.unset;

  /// The address requests currently go to.
  BackendAddress get backend => _backend;

  /// Points this client at [backend].
  ///
  /// Called once at startup and again whenever Settings saves a new address, so
  /// the HTTP core never goes stale behind the user's choice.
  void configure(BackendAddress backend) => _backend = backend;

  /// Requests [path] and discards the response body.
  ///
  /// For endpoints where only the status matters, such as probing whether a
  /// stored session is still valid.
  Future<void> get(String path) async {
    await _send(() => _dio.get<Object?>(path));
  }

  /// Fetches one JSON object from [path] and decodes it with [decode].
  Future<T> getObject<T>(String path, JsonDecoder<T> decode) async =>
      decode(_asObject(await _send(() => _dio.get<Object?>(path))));

  /// Fetches a JSON array from [path] and decodes each element with [decode].
  Future<List<T>> getList<T>(String path, JsonDecoder<T> decode) async {
    final data = await _send(() => _dio.get<Object?>(path));
    if (data is! List) {
      throw const NetworkFailure('The server did not return a list');
    }
    return [for (final element in data) decode(_asObject(element))];
  }

  /// Posts [body] to [path], ignoring any response body.
  Future<void> post(String path, {JsonObject? body}) async {
    await _send(() => _dio.post<Object?>(path, data: body));
  }

  /// Posts [body] to [path] and decodes the response with [decode].
  Future<T> postObject<T>(
    String path,
    JsonDecoder<T> decode, {
    JsonObject? body,
  }) async => decode(
    _asObject(await _send(() => _dio.post<Object?>(path, data: body))),
  );

  /// Posts raw [bytes] to [path] under [contentType], decoding the reply with
  /// [decode].
  ///
  /// The one call in the app that does not send JSON. Voice answers are posted
  /// as the recording itself under an `audio/*` content type, because the
  /// backend registers a raw body parser for exactly that and reads the request
  /// body as a buffer — a multipart envelope would arrive as bytes it does not
  /// know how to unwrap.
  Future<T> postBytes<T>(
    String path,
    JsonDecoder<T> decode, {
    required List<int> bytes,
    required String contentType,
  }) async => decode(
    _asObject(
      await _send(
        () => _dio.post<Object?>(
          path,
          data: Stream.fromIterable([bytes]),
          options: Options(
            headers: {
              Headers.contentTypeHeader: contentType,
              Headers.contentLengthHeader: bytes.length,
            },
          ),
        ),
      ),
    ),
  );

  /// Downloads [path] as raw bytes instead of JSON — the diary export
  /// (`GET /export`) is the only endpoint that answers a file rather than an
  /// object.
  ///
  /// Reads the filename the server suggests off `Content-Disposition` when it
  /// sends one, so a caller never has to compose its own.
  Future<DownloadedFile> getBytes(String path) async {
    final response = await _sendRaw(
      () => _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    // `_sendRaw` is shared with every JSON-returning method, so its return
    // type is erased to `Response<Object?>` — the cast below recovers what
    // `responseType: ResponseType.bytes` above actually guarantees dio hands
    // back.
    final data = response.data;
    return DownloadedFile(
      bytes: Uint8List.fromList(data is List<int> ? data : const []),
      filename: _filenameFromContentDisposition(
        response.headers.value('content-disposition'),
      ),
    );
  }

  /// Puts [body] to [path], ignoring any response body.
  Future<void> put(String path, {JsonObject? body}) async {
    await _send(() => _dio.put<Object?>(path, data: body));
  }

  /// Patches [path] with [body] and decodes the response with [decode].
  ///
  /// `PATCH` rather than `PUT` because these are partial updates: an absent
  /// field means "leave it alone", which is the contract the diary's entry
  /// edits are built on. A `PUT` would have to carry the whole entry, and a
  /// client that sent a stale field it never meant to touch would quietly
  /// overwrite it.
  Future<T> patchObject<T>(
    String path,
    JsonDecoder<T> decode, {
    JsonObject? body,
  }) async => decode(
    _asObject(await _send(() => _dio.patch<Object?>(path, data: body))),
  );

  /// Deletes [path], ignoring any response body.
  Future<void> delete(String path) async {
    await _send(() => _dio.delete<Object?>(path));
  }

  /// Deletes [path] and decodes what the server sends back with [decode].
  ///
  /// Most deletes answer `204` and there is nothing to read. Some answer with
  /// the resource as it now stands — removing one alias from a topic returns
  /// the topic — and reading that reply saves the caller a round trip whose
  /// only purpose would be to learn what the server already said.
  Future<T> deleteObject<T>(String path, JsonDecoder<T> decode) async =>
      decode(_asObject(await _send(() => _dio.delete<Object?>(path))));

  /// Forgets every stored cookie, ending the local half of a session.
  Future<void> clearSession() => cookieJar.deleteAll();

  JsonObject _asObject(Object? data) {
    if (data is JsonObject) return data;
    throw const NetworkFailure('The server did not return a JSON object');
  }

  Future<Object?> _send(Future<Response<Object?>> Function() request) async =>
      (await _sendRaw(request)).data;

  /// The shared core [_send] wraps: same failure handling, but hands back the
  /// whole [Response] rather than only its body — [getBytes] needs the
  /// headers too, to read `Content-Disposition`.
  Future<Response<Object?>> _sendRaw(
    Future<Response<Object?>> Function() request,
  ) async {
    final Response<Object?> response;
    try {
      response = await request();
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiError) throw error;
      throw NetworkFailure(_networkMessage(e));
    }

    final status = response.statusCode ?? 0;
    return switch (status) {
      >= 200 && < 300 => response,
      401 => throw const Unauthorized(),
      _ => throw HttpFailure(
        _errorMessage(response, status),
        status,
        response.data,
      ),
    };
  }

  static String _networkMessage(DioException e) =>
      'Could not reach the server (${e.message ?? e.type.name})';

  /// Parses the `filename="..."` parameter off a
  /// `Content-Disposition: attachment; filename="..."` header — the exact
  /// shape `GET /export` sends (`export.controller.ts`). `null` when [header]
  /// is `null` or carries no filename; the caller falls back to a name of its
  /// own in that case.
  static String? _filenameFromContentDisposition(String? header) {
    if (header == null) return null;
    return RegExp('filename="([^"]+)"').firstMatch(header)?.group(1);
  }

  static String _errorMessage(Response<Object?> response, int status) =>
      switch (response.data) {
        // The error-body contract every backend in the portfolio follows. Two
        // shapes are in the wild: a bare string, and the envelope this app's
        // backend sends, `{"error": {"code": ..., "message": ...}}`.
        {'error': final String message} => message,
        {'error': {'message': final String message}} => message,
        _ => 'Request failed (HTTP $status)',
      };

  /// Probes [backend]'s health endpoint without saving or using it.
  ///
  /// Deliberately independent of [configure] and of the cookie jar, so the
  /// Settings screen can test an address the user has typed but not yet saved.
  Future<ConnectionResult> testConnection(BackendAddress backend) async {
    final probe = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        validateStatus: (_) => true,
        headers: const {'Accept': 'application/json'},
      ),
    )..httpClientAdapter = _dio.httpClientAdapter;
    try {
      final response = await probe.get<Object?>(
        '${backend.origin}${AppConfig.healthPath}',
      );
      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        return ConnectionResult.ok('Connected (HTTP $status)');
      }
      return ConnectionResult.failed('Server replied HTTP $status');
    } on DioException catch (e) {
      return ConnectionResult.failed(_networkMessage(e));
    } finally {
      probe.close();
    }
  }
}

/// The outcome of a Settings-screen connectivity test.
class const ConnectionResult._(final bool ok, final String detail) {
  /// A successful probe, described by [detail].
  factory ok(String detail) => ConnectionResult._(true, detail);

  /// A failed probe, described by [detail].
  factory failed(String detail) => ConnectionResult._(false, detail);
}

/// The result of [ApiClient.getBytes]: a file's raw content and the name the
/// server suggested for it.
class DownloadedFile {
  /// Creates a downloaded file.
  const DownloadedFile({required this.bytes, required this.filename});

  /// The file's raw content.
  final Uint8List bytes;

  /// The name from `Content-Disposition`, or `null` if the response carried
  /// none.
  final String? filename;
}
