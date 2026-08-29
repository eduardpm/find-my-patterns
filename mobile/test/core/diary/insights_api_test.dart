import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/feelings_api.dart';
import 'package:find_my_patterns/core/diary/insights_api.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';

void main() {
  final feelingsBody = {
    'feelings': [
      {
        'key': 'anxious',
        'label': 'Anxious',
        'valence': 'negative',
        'group_key': 'tense',
      },
    ],
  };

  ApiClient clientFor(FakeHttpAdapter adapter) {
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
    client.configure(const BackendAddress(host: '10.0.2.2'));
    return client;
  }

  ({InsightsApi api, FakeHttpAdapter adapter}) apiFor(List<FakeReply> replies) {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsBody),
      ...replies,
    ]);
    final client = clientFor(adapter);
    final api = InsightsApi(client, FeelingsApi(client));
    return (api: api, adapter: adapter);
  }

  group('insights', () {
    test('decodes the patterns, withdrawals and constants', () async {
      final env = apiFor([
        FakeReply(
          200,
          body: {
            'patterns': [
              {
                'id': 'p1',
                'topic': 'meetings',
                'feeling': 'anxious',
                'occurrence_count': 8,
                'direction': 'change',
                'narrative_text': 'narrative',
                'suggestion_text': 'suggestion',
                'last_updated_at': '2026-08-26T09:00:00.000000',
              },
            ],
            'withdrawals': <Object?>[],
            'new_withdrawal_count': 0,
            'insufficient_data': false,
            'constants': {'recency_window_days': 14},
          },
        ),
      ]);

      final result = await env.api.insights();

      expect(
        result.patterns.single.feeling,
        const Feeling('anxious', 'Anxious', Valence.negative, 'tense'),
      );
      expect(result.constants.recencyWindowDays, 14);
      expect(env.adapter.requests.last.path, '/insights');
    });
  });

  group('whenInsights', () {
    test('decodes the weekday and time-of-day buckets', () async {
      // Neither whenInsights nor acknowledgeWithdrawals resolve a feeling
      // key, so unlike insights() they need no feelings reply queued ahead
      // of them.
      final adapter = FakeHttpAdapter([
        FakeReply(
          200,
          body: {
            'window_days': 30,
            'total_entries': 12,
            'weekdays': [
              {'key': 'monday', 'label': 'Monday', 'entry_count': 5},
            ],
          },
        ),
      ]);
      final client = clientFor(adapter);
      final api = InsightsApi(client, FeelingsApi(client));

      final when = await api.whenInsights();

      expect(when.totalEntries, 12);
      expect(when.weekdays.single.key, 'monday');
      expect(adapter.requests.last.path, '/insights/when');
    });
  });

  group('acknowledgeWithdrawals', () {
    test('posts to the acknowledge endpoint', () async {
      final adapter = FakeHttpAdapter([FakeReply(204)]);
      final client = clientFor(adapter);
      final api = InsightsApi(client, FeelingsApi(client));
      await api.acknowledgeWithdrawals();

      final request = adapter.requests.last;
      expect(request.method, 'POST');
      expect(request.path, '/insights/withdrawals/acknowledge');
    });
  });
}
