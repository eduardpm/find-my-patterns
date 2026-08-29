import 'dart:io';

import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/network/api_error.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';

/// A model decoded from the fake backend's replies.
class Entry {
  const Entry(this.id);

  factory Entry.fromJson(JsonObject json) => Entry(json['id']! as String);

  final String id;
}

void main() {
  const backend = BackendAddress(host: '10.0.2.2');

  /// Builds a client whose Dio is wired to [adapter], pointed at [backend]
  /// unless [configured] is false.
  ApiClient clientFor(FakeHttpAdapter adapter, {bool configured = true}) {
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ApiClient(dio: dio);
    if (configured) client.configure(backend);
    return client;
  }

  group('configure', () {
    test('starts unset and adopts the address it is given', () {
      final client = clientFor(FakeHttpAdapter([]), configured: false);
      expect(client.backend, BackendAddress.unset);
      client.configure(backend);
      expect(client.backend, backend);
    });

    test('sends requests to the configured origin', () async {
      final adapter = FakeHttpAdapter.always(const FakeReply(200, body: {}));
      await clientFor(adapter).get('/api/thing');
      expect(
        adapter.requests.single.uri.toString(),
        'http://10.0.2.2:8000/api/thing',
      );
    });

    test('a later configure redirects subsequent requests', () async {
      final adapter = FakeHttpAdapter.always(const FakeReply(200, body: {}));
      final client = clientFor(adapter)
        ..configure(const BackendAddress(host: 'elsewhere', port: 9000));
      await client.get('/api/thing');
      expect(adapter.requests.single.uri.host, 'elsewhere');
    });
  });

  group('unconfigured backend', () {
    test('rejects before reaching the network', () async {
      final adapter = FakeHttpAdapter([]);
      await expectLater(
        clientFor(adapter, configured: false).get('/api/thing'),
        throwsA(isA<BackendNotConfigured>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('reads', () {
    test('getObject decodes the response body', () async {
      final client = clientFor(
        FakeHttpAdapter([
          const FakeReply(200, body: {'id': 'a'}),
        ]),
      );
      final entry = await client.getObject('/api/entry', Entry.fromJson);
      expect(entry.id, 'a');
    });

    test('getObject rejects a non-object body', () async {
      final client = clientFor(
        FakeHttpAdapter([
          const FakeReply(200, body: [1, 2]),
        ]),
      );
      await expectLater(
        client.getObject('/api/entry', Entry.fromJson),
        throwsA(
          isA<NetworkFailure>().having(
            (e) => e.message,
            'message',
            contains('JSON object'),
          ),
        ),
      );
    });

    test('getList decodes every element', () async {
      final client = clientFor(
        FakeHttpAdapter([
          const FakeReply(
            200,
            body: [
              {'id': 'a'},
              {'id': 'b'},
            ],
          ),
        ]),
      );
      final entries = await client.getList('/api/entries', Entry.fromJson);
      expect(entries.map((e) => e.id), ['a', 'b']);
    });

    test('getList rejects a body that is not a list', () async {
      final client = clientFor(
        FakeHttpAdapter([
          const FakeReply(200, body: {'id': 'a'}),
        ]),
      );
      await expectLater(
        client.getList('/api/entries', Entry.fromJson),
        throwsA(
          isA<NetworkFailure>().having(
            (e) => e.message,
            'message',
            contains('list'),
          ),
        ),
      );
    });

    test('get discards the body', () async {
      final client = clientFor(
        FakeHttpAdapter([const FakeReply(204)]),
      );
      await expectLater(client.get('/api/session'), completes);
    });
  });

  group('writes', () {
    test('post sends the body and ignores the reply', () async {
      final adapter = FakeHttpAdapter([const FakeReply(200, body: {})]);
      await clientFor(adapter).post('/api/session', body: {'password': 'x'});
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.data, {'password': 'x'});
    });

    test('postObject decodes the reply', () async {
      final client = clientFor(
        FakeHttpAdapter([
          const FakeReply(201, body: {'id': 'new'}),
        ]),
      );
      final entry = await client.postObject(
        '/api/entries',
        Entry.fromJson,
        body: {'id': 'new'},
      );
      expect(entry.id, 'new');
    });

    test('put sends the body', () async {
      final adapter = FakeHttpAdapter([const FakeReply(200, body: {})]);
      await clientFor(adapter).put('/api/entry', body: {'id': 'a'});
      expect(adapter.requests.single.method, 'PUT');
    });

    test('delete sends the request', () async {
      final adapter = FakeHttpAdapter([const FakeReply(204)]);
      await clientFor(adapter).delete('/api/session');
      expect(adapter.requests.single.method, 'DELETE');
    });

    test('patchObject sends a partial body and decodes the reply', () async {
      final adapter = FakeHttpAdapter([
        const FakeReply(200, body: {'id': 'patched'}),
      ]);
      final entry = await clientFor(adapter).patchObject(
        '/entries/a',
        Entry.fromJson,
        body: {'version': 3},
      );
      final request = adapter.requests.single;
      expect(entry.id, 'patched');
      expect(request.method, 'PATCH');
      expect(request.data, {'version': 3});
    });

    test('deleteObject decodes the resource the server returns', () async {
      final adapter = FakeHttpAdapter([
        const FakeReply(200, body: {'id': 'topic-after-removal'}),
      ]);
      final topic = await clientFor(
        adapter,
      ).deleteObject('/topics/t1/aliases/gym', Entry.fromJson);
      expect(topic.id, 'topic-after-removal');
      expect(adapter.requests.single.method, 'DELETE');
    });

    test(
      'postBytes sends the bytes under the content type it is given',
      () async {
        final adapter = FakeHttpAdapter([
          const FakeReply(202, body: {'id': 'job-1'}),
        ]);
        final entry = await clientFor(adapter).postBytes(
          '/transcriptions',
          Entry.fromJson,
          bytes: const [1, 2, 3, 4],
          contentType: 'audio/mp4',
        );
        final request = adapter.requests.single;
        expect(entry.id, 'job-1');
        expect(request.method, 'POST');
        expect(request.headers[Headers.contentTypeHeader], 'audio/mp4');
        expect(request.headers[Headers.contentLengthHeader], 4);
      },
    );
  });

  group('failures', () {
    test('401 becomes Unauthorized', () async {
      final client = clientFor(FakeHttpAdapter([const FakeReply(401)]));
      await expectLater(
        client.get('/api/session'),
        throwsA(
          isA<Unauthorized>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('another 4xx becomes HttpFailure carrying the status', () async {
      final client = clientFor(FakeHttpAdapter([const FakeReply(404)]));
      await expectLater(
        client.get('/api/thing'),
        throwsA(
          isA<HttpFailure>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', contains('HTTP 404')),
        ),
      );
    });

    test("uses the backend's error message when it sends one", () async {
      final client = clientFor(
        FakeHttpAdapter([
          const FakeReply(500, body: {'error': 'the database is on fire'}),
        ]),
      );
      await expectLater(
        client.get('/api/thing'),
        throwsA(
          isA<HttpFailure>().having(
            (e) => e.message,
            'message',
            'the database is on fire',
          ),
        ),
      );
    });

    test('reads the message out of a nested error envelope', () async {
      final client = clientFor(
        FakeHttpAdapter([
          const FakeReply(
            409,
            body: {
              'error': {
                'code': 'stale_entry',
                'message': 'Someone got there first',
              },
            },
          ),
        ]),
      );
      await expectLater(
        client.get('/entries/a'),
        throwsA(
          isA<HttpFailure>().having(
            (e) => e.message,
            'message',
            'Someone got there first',
          ),
        ),
      );
    });

    test(
      'keeps the decoded body so a caller can read what else it carries',
      () async {
        final client = clientFor(
          FakeHttpAdapter([
            const FakeReply(
              409,
              body: {
                'error': {'code': 'stale_entry', 'message': 'Out of date'},
                'current': {'id': 'entry-1'},
              },
            ),
          ]),
        );
        await expectLater(
          client.get('/entries/entry-1'),
          throwsA(
            isA<HttpFailure>().having(
              (e) => (e.body! as Map<String, Object?>)['current'],
              'body.current',
              {'id': 'entry-1'},
            ),
          ),
        );
      },
    );

    test('a transport failure becomes NetworkFailure', () async {
      final client = clientFor(
        FakeHttpAdapter([const FakeReply.networkError()]),
      );
      await expectLater(
        client.get('/api/thing'),
        throwsA(
          isA<NetworkFailure>().having(
            (e) => e.message,
            'message',
            contains('Could not reach the server'),
          ),
        ),
      );
    });
  });

  group('sessions', () {
    test('the cookie jar rides along and can be cleared', () async {
      final client = clientFor(FakeHttpAdapter.always(const FakeReply(200)));
      await client.cookieJar.saveFromResponse(
        Uri.parse('http://10.0.2.2:8000'),
        [Cookie('session', 'abc')],
      );
      expect(
        await client.cookieJar.loadForRequest(
          Uri.parse('http://10.0.2.2:8000'),
        ),
        isNotEmpty,
      );
      await client.clearSession();
      expect(
        await client.cookieJar.loadForRequest(
          Uri.parse('http://10.0.2.2:8000'),
        ),
        isEmpty,
      );
    });
  });

  group('testConnection', () {
    test('reports success for a healthy server', () async {
      final client = clientFor(
        FakeHttpAdapter.always(const FakeReply(200, body: {'ok': true})),
        configured: false,
      );
      final result = await client.testConnection(backend);
      expect(result.ok, isTrue);
      expect(result.detail, contains('200'));
    });

    test('reports the status when the server refuses', () async {
      final client = clientFor(
        FakeHttpAdapter.always(const FakeReply(503)),
        configured: false,
      );
      final result = await client.testConnection(backend);
      expect(result.ok, isFalse);
      expect(result.detail, contains('503'));
    });

    test('reports a transport failure', () async {
      final client = clientFor(
        FakeHttpAdapter.always(const FakeReply.networkError()),
        configured: false,
      );
      final result = await client.testConnection(backend);
      expect(result.ok, isFalse);
      expect(result.detail, contains('Could not reach'));
    });

    test('works without the client having been configured', () async {
      final adapter = FakeHttpAdapter.always(const FakeReply(200, body: {}));
      final client = clientFor(adapter, configured: false);
      expect((await client.testConnection(backend)).ok, isTrue);
      expect(adapter.requests.single.uri.host, '10.0.2.2');
    });
  });
}
