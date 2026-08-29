import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/diary/guiding_questions_api.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';

void main() {
  ApiClient clientFor(FakeHttpAdapter adapter) {
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
    client.configure(const BackendAddress(host: '10.0.2.2'));
    return client;
  }

  final body = {
    'questions': [
      {
        'key': 'general',
        'category': 'general',
        'prompt_text': 'How was your day?',
        'trigger_keywords': <String>[],
        'is_mandatory': true,
      },
      {
        'key': 'work',
        'category': 'small_influences',
        'prompt_text': 'Anything at work stand out?',
        'trigger_keywords': ['work'],
        'is_mandatory': false,
      },
    ],
  };

  test('fetches and decodes the library', () async {
    final adapter = FakeHttpAdapter([FakeReply(200, body: body)]);
    final api = GuidingQuestionsApi(clientFor(adapter));

    final library = await api.library();

    expect(library.map((q) => q.key), ['general', 'work']);
    expect(library.first.isMandatory, isTrue);
    expect(adapter.requests.single.path, '/guiding-questions');
  });

  test('caches the library for the life of the object', () async {
    final adapter = FakeHttpAdapter([FakeReply(200, body: body)]);
    final api = GuidingQuestionsApi(clientFor(adapter));

    await api.library();
    await api.library();

    expect(adapter.requests, hasLength(1));
  });

  test('forceRefresh bypasses the cache', () async {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: body),
      FakeReply(200, body: body),
    ]);
    final api = GuidingQuestionsApi(clientFor(adapter));

    await api.library();
    await api.library(forceRefresh: true);

    expect(adapter.requests, hasLength(2));
  });

  test('two concurrent callers on a cold cache produce one request', () async {
    final adapter = FakeHttpAdapter([FakeReply(200, body: body)]);
    final api = GuidingQuestionsApi(clientFor(adapter));

    final results = await Future.wait([api.library(), api.library()]);

    expect(adapter.requests, hasLength(1));
    expect(results[0].map((q) => q.key), results[1].map((q) => q.key));
  });
}
