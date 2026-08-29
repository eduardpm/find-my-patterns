import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/diary/topics_api.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';

void main() {
  ({TopicsApi api, FakeHttpAdapter adapter}) apiFor(List<FakeReply> replies) {
    final adapter = FakeHttpAdapter(replies);
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter)
      ..configure(const BackendAddress(host: '10.0.2.2'));
    return (api: TopicsApi(client), adapter: adapter);
  }

  group('list', () {
    test('reads the topic list', () async {
      final env = apiFor([
        FakeReply(
          200,
          body: {
            'topics': [
              {
                'id': 't1',
                'name': 'exercise',
                'aliases': ['gym'],
                'entry_count': 4,
              },
            ],
          },
        ),
      ]);

      final topics = await env.api.list();

      expect(topics.single.name, 'exercise');
      expect(env.adapter.requests.single.path, '/topics');
    });
  });

  group('addAlias', () {
    test('posts the alias to the topic', () async {
      final env = apiFor([
        FakeReply(
          200,
          body: {
            'id': 't1',
            'name': 'exercise',
            'aliases': ['gym'],
            'entry_count': 4,
          },
        ),
      ]);

      final topic = await env.api.addAlias('t1', 'gym');

      expect(topic.aliases, ['gym']);
      final request = env.adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/topics/t1/aliases');
      expect(request.data, {'alias': 'gym'});
    });
  });

  group('removeAlias', () {
    test(
      'deletes the alias (URL-encoded in the path) and decodes the returned topic',
      () async {
        final env = apiFor([
          FakeReply(
            200,
            body: {
              'id': 't1',
              'name': 'exercise',
              'aliases': <String>[],
              'entry_count': 4,
            },
          ),
        ]);

        final topic = await env.api.removeAlias('t1', 'gym session');

        expect(topic.aliases, isEmpty);
        final request = env.adapter.requests.single;
        expect(request.method, 'DELETE');
        expect(request.path, '/topics/t1/aliases/gym%20session');
      },
    );
  });
}
