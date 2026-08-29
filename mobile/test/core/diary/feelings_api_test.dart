import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/diary/feelings_api.dart';
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

  final groupedBody = {
    'groups': [
      {
        'key': 'uplifted',
        'label': 'Uplifted',
        'valence': 'positive',
        'feelings': [
          {
            'key': 'happy',
            'label': 'Happy',
            'valence': 'positive',
            'group_key': 'uplifted',
          },
          {
            'key': 'grateful',
            'label': 'Grateful',
            'valence': 'positive',
            'group_key': 'uplifted',
          },
        ],
      },
    ],
    'feelings': [
      {
        'key': 'happy',
        'label': 'Happy',
        'valence': 'positive',
        'group_key': 'uplifted',
      },
      {
        'key': 'grateful',
        'label': 'Grateful',
        'valence': 'positive',
        'group_key': 'uplifted',
      },
    ],
  };

  group('catalog', () {
    test('fetches and decodes the vocabulary', () async {
      final adapter = FakeHttpAdapter([FakeReply(200, body: groupedBody)]);
      final api = FeelingsApi(clientFor(adapter));

      final catalog = await api.catalog();

      expect(catalog.feelings.map((f) => f.key), ['happy', 'grateful']);
      expect(catalog.groups.single.key, 'uplifted');
      expect(adapter.requests.single.path, '/feelings');
    });

    test('caches the catalog for the life of the object', () async {
      final adapter = FakeHttpAdapter([FakeReply(200, body: groupedBody)]);
      final api = FeelingsApi(clientFor(adapter));

      await api.catalog();
      await api.catalog();

      expect(adapter.requests, hasLength(1));
    });

    test('forceRefresh bypasses the cache', () async {
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: groupedBody),
        FakeReply(200, body: groupedBody),
      ]);
      final api = FeelingsApi(clientFor(adapter));

      await api.catalog();
      await api.catalog(forceRefresh: true);

      expect(adapter.requests, hasLength(2));
    });

    test(
      'two concurrent callers on a cold cache produce one request',
      () async {
        final adapter = FakeHttpAdapter([FakeReply(200, body: groupedBody)]);
        final api = FeelingsApi(clientFor(adapter));

        final results = await Future.wait([api.catalog(), api.catalog()]);

        expect(adapter.requests, hasLength(1));
        expect(results[0].feelings, results[1].feelings);
      },
    );
  });

  group('feelings', () {
    test('returns the flat vocabulary', () async {
      final adapter = FakeHttpAdapter([FakeReply(200, body: groupedBody)]);
      final api = FeelingsApi(clientFor(adapter));

      final feelings = await api.feelings();

      expect(feelings.map((f) => f.key), ['happy', 'grateful']);
    });
  });

  group('groups', () {
    test('returns the nested vocabulary', () async {
      final adapter = FakeHttpAdapter([FakeReply(200, body: groupedBody)]);
      final api = FeelingsApi(clientFor(adapter));

      final groups = await api.groups();

      expect(groups.single.key, 'uplifted');
      expect(groups.single.feelings.map((f) => f.key), ['happy', 'grateful']);
    });
  });

  test(
    'an unmigrated backend serving a flat list still yields a usable catalog',
    () async {
      final flatBody = {
        'feelings': [
          {'key': 'happy', 'label': 'Happy', 'valence': 'positive'},
        ],
      };
      final adapter = FakeHttpAdapter([FakeReply(200, body: flatBody)]);
      final api = FeelingsApi(clientFor(adapter));

      final catalog = await api.catalog();

      expect(catalog.groups, isEmpty);
      expect(catalog.fromKey('happy')?.groupKey, '');
    },
  );
}
