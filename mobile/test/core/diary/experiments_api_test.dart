import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/diary/experiment.dart';
import 'package:find_my_patterns/core/diary/experiments_api.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/network/api_error.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';

void main() {
  ({ExperimentsApi api, FakeHttpAdapter adapter}) apiFor(
    List<FakeReply> replies,
  ) {
    final adapter = FakeHttpAdapter(replies);
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter)
      ..configure(const BackendAddress(host: '10.0.2.2'));
    return (api: ExperimentsApi(client), adapter: adapter);
  }

  Map<String, Object?> experimentJson({String status = 'active'}) => {
    'id': 'experiment-1',
    'pattern_topic': 'exercise',
    'pattern_feeling': 'exhausted',
    'hypothesis_kind': 'more_of',
    'start_date': '2026-08-01',
    'end_date': '2026-08-07',
    'status': status,
    'created_at': '2026-08-01T09:00:00Z',
    'constants': {
      'default_length_days': 7,
      'min_length_days': 7,
      'max_length_days': 28,
      'min_bucket_entries': 3,
    },
  };

  group('create', () {
    test(
      'posts the pattern, hypothesis and length, decoding the result',
      () async {
        final env = apiFor([FakeReply(201, body: experimentJson())]);

        final experiment = await env.api.create(
          patternTopic: 'exercise',
          patternFeeling: 'exhausted',
          hypothesisKind: HypothesisKind.moreOf,
          lengthDays: 14,
        );

        expect(experiment.id, 'experiment-1');
        final request = env.adapter.requests.single;
        expect(request.method, 'POST');
        expect(request.path, '/experiments');
        expect(request.data, {
          'pattern_topic': 'exercise',
          'pattern_feeling': 'exhausted',
          'hypothesis_kind': 'more_of',
          'length_days': 14,
        });
      },
    );

    test('omits length_days when none was given', () async {
      final env = apiFor([FakeReply(201, body: experimentJson())]);

      await env.api.create(
        patternTopic: 'exercise',
        patternFeeling: 'exhausted',
        hypothesisKind: HypothesisKind.lessOf,
      );

      final request = env.adapter.requests.single;
      expect(request.data, {
        'pattern_topic': 'exercise',
        'pattern_feeling': 'exhausted',
        'hypothesis_kind': 'less_of',
      });
    });

    test('a 422 rejection surfaces as an HttpFailure carrying the backend '
        "message -- eligibility is the backend's call", () async {
      final env = apiFor([
        FakeReply(
          422,
          body: {
            'error': {
              'code': 'validation_error',
              'message':
                  '"reading" / "calm" is not a currently qualifying pattern.',
            },
          },
        ),
      ]);

      await expectLater(
        env.api.create(
          patternTopic: 'reading',
          patternFeeling: 'calm',
          hypothesisKind: HypothesisKind.lessOf,
        ),
        throwsA(
          isA<HttpFailure>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having(
                (e) => e.message,
                'message',
                '"reading" / "calm" is not a currently qualifying pattern.',
              ),
        ),
      );
    });
  });

  group('active', () {
    test('decodes the active experiment', () async {
      final env = apiFor([FakeReply(200, body: experimentJson())]);

      final experiment = await env.api.active();

      expect(experiment, isNotNull);
      expect(experiment!.id, 'experiment-1');
      expect(env.adapter.requests.single.path, '/experiments/active');
    });

    test(
      'a 404 (nothing active) decodes to null, not a thrown error',
      () async {
        final env = apiFor([
          FakeReply(
            404,
            body: {
              'error': {
                'code': 'not_found',
                'message': 'No experiment is currently active.',
              },
            },
          ),
        ]);

        expect(await env.api.active(), isNull);
      },
    );

    test('any other failure still propagates', () async {
      final env = apiFor([const FakeReply.networkError()]);

      await expectLater(env.api.active(), throwsA(isA<NetworkFailure>()));
    });

    test(
      'a 200 whose body does not decode as an experiment also reads as '
      'null, rather than crashing',
      () async {
        final env = apiFor([FakeReply(200, body: const {})]);

        expect(await env.api.active(), isNull);
      },
    );
  });

  group('abandon', () {
    test('posts to the abandon route and decodes the result', () async {
      final env = apiFor([
        FakeReply(200, body: experimentJson(status: 'abandoned')),
      ]);

      final experiment = await env.api.abandon('experiment-1');

      expect(experiment.status, ExperimentStatus.abandoned);
      final request = env.adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/experiments/experiment-1/abandon');
    });
  });

  group('results', () {
    test('reads the results route and decodes the payload', () async {
      final env = apiFor([
        FakeReply(
          200,
          body: {
            'experiment': experimentJson(status: 'finished'),
            'experiment_window': {
              'start_date': '2026-08-01',
              'end_date': '2026-08-07',
              'total_days': 7,
              'days_with_topic': 4,
              'present_count': 1,
              'present_total': 4,
              'absent_count': 1,
              'absent_total': 2,
              'present_rate': 0.25,
              'absent_rate': 0.5,
            },
            'baseline_window': {
              'start_date': '2026-07-25',
              'end_date': '2026-07-31',
              'total_days': 7,
              'days_with_topic': 5,
              'present_count': 3,
              'present_total': 5,
              'absent_count': 1,
              'absent_total': 2,
              'present_rate': 0.6,
              'absent_rate': 0.5,
            },
            'verdict_text': 'A verdict.',
            'insufficient_data': false,
            'constants': {
              'default_length_days': 7,
              'min_length_days': 7,
              'max_length_days': 28,
              'min_bucket_entries': 3,
            },
          },
        ),
      ]);

      final results = await env.api.results('experiment-1');

      expect(results.verdictText, 'A verdict.');
      expect(results.experiment.status, ExperimentStatus.finished);
      expect(
        env.adapter.requests.single.path,
        '/experiments/experiment-1/results',
      );
    });
  });
}
