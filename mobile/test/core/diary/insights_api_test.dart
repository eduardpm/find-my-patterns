import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/digest.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/feelings_api.dart';
import 'package:find_my_patterns/core/diary/insights_api.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/network/api_error.dart';
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

  group('series', () {
    test('requests day granularity over the given range and decodes the '
        'points', () async {
      final adapter = FakeHttpAdapter([
        FakeReply(
          200,
          body: {
            'granularity': 'day',
            'points': [
              {'date': '2026-08-25', 'score': 1, 'entry_count': 1},
              {'date': '2026-08-28', 'score': null, 'entry_count': 15},
            ],
            'constants': <String, Object?>{},
          },
        ),
      ]);
      final client = clientFor(adapter);
      final api = InsightsApi(client, FeelingsApi(client));

      final series = await api.series(
        from: const CalendarDate(2026, 8, 1),
        to: const CalendarDate(2026, 8, 28),
      );

      expect(series.points, hasLength(2));
      expect(series.points.first.score, 1.0);
      expect(series.points.last.score, isNull);
      expect(series.points.last.entryCount, 15);

      final request = adapter.requests.last;
      expect(request.uri.path, '/insights/series');
      expect(request.uri.queryParameters, {
        'from': '2026-08-01',
        'to': '2026-08-28',
        'granularity': 'day',
      });
    });

    // The repo-wide convention: a validation failure answers 422, and it
    // surfaces as the same sealed `ApiError` every other failure does.
    test('a 422 validation failure surfaces as an HttpFailure', () async {
      final adapter = FakeHttpAdapter([
        FakeReply(
          422,
          body: {'error': "Invalid granularity: 'hour'"},
        ),
      ]);
      final client = clientFor(adapter);
      final api = InsightsApi(client, FeelingsApi(client));

      await expectLater(
        api.series(
          from: const CalendarDate(2026, 8, 1),
          to: const CalendarDate(2026, 8, 28),
        ),
        throwsA(
          isA<HttpFailure>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having(
                (e) => e.message,
                'message',
                "Invalid granularity: 'hour'",
              ),
        ),
      );
    });
  });

  group('digest (R-2)', () {
    test('decodes the empty shape', () async {
      final env = apiFor([
        FakeReply(200, body: {'empty': true, 'entry_count': 0}),
      ]);

      final digest = await env.api.digest();

      expect(digest.empty, isTrue);
      expect(digest.entryCount, 0);
      expect(digest.week, isNull);
      expect(digest.highlight, isNull);
      expect(digest.recommendation, isNull);
      expect(digest.movement, isNull);
      expect(env.adapter.requests.last.path, '/insights/digest');
    });

    test(
      'decodes a full response: highlight, recommendation and movement',
      () async {
        final env = apiFor([
          FakeReply(
            200,
            body: {
              'empty': false,
              'week': '2026-08-24',
              'entry_count': 10,
              'highlight': {
                'pattern_ref': 'p1',
                'kind': 'forward',
                'topic': 'reading',
                'feeling': 'anxious',
                'week_count': 3,
                'lift': 1.5,
                'sentence': 'reading came up in 3 entries this week.',
              },
              'recommendation': {
                'action_topic': 'reading',
                'headline': 'Keep doing reading',
                'sentence': 'On days with reading, calm is 4.5x more likely.',
                'pattern_ref': 'p1',
              },
              'movement': {
                'feeling': 'anxious',
                'current_count': 3,
                'previous_count': 6,
                'direction': 'down',
                'sentence':
                    'anxious appeared in 3 entries this week, down '
                    'from 6 last week.',
              },
            },
          ),
        ]);

        final digest = await env.api.digest();

        expect(digest.empty, isFalse);
        expect(digest.entryCount, 10);
        expect(digest.week, const CalendarDate(2026, 8, 24));
        expect(digest.highlight!.patternRef, 'p1');
        expect(digest.highlight!.kind, PatternKind.forward);
        expect(digest.highlight!.topic, 'reading');
        expect(digest.highlight!.feeling!.key, 'anxious');
        expect(digest.highlight!.weekCount, 3);
        expect(digest.highlight!.lift, 1.5);
        expect(
          digest.highlight!.sentence,
          'reading came up in 3 entries this week.',
        );
        expect(digest.recommendation!.headline, 'Keep doing reading');
        expect(digest.recommendation!.patternRef, 'p1');
        expect(digest.movement!.feeling!.key, 'anxious');
        expect(digest.movement!.currentCount, 3);
        expect(digest.movement!.previousCount, 6);
        expect(digest.movement!.direction, DigestMovementDirection.down);
      },
    );

    test('every part is absent when the backend omits it', () async {
      final env = apiFor([
        FakeReply(
          200,
          body: {'empty': false, 'week': '2026-08-24', 'entry_count': 1},
        ),
      ]);

      final digest = await env.api.digest();

      expect(digest.highlight, isNull);
      expect(digest.recommendation, isNull);
      expect(digest.movement, isNull);
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
