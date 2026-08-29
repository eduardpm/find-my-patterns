import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/diary/transcription.dart';
import 'package:find_my_patterns/core/diary/transcriptions_api.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/network/api_error.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';

void main() {
  ({TranscriptionsApi api, FakeHttpAdapter adapter}) apiFor(
    List<FakeReply> replies,
  ) {
    final adapter = FakeHttpAdapter(replies);
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter)
      ..configure(const BackendAddress(host: '10.0.2.2'));
    return (api: TranscriptionsApi(client), adapter: adapter);
  }

  // No real waiting anywhere in this file (Article 3): every call passes a
  // no-op delay.
  Future<void> noDelay(Duration duration) async {}

  group('start', () {
    test('posts the audio bytes under their content type', () async {
      final env = apiFor([
        FakeReply(202, body: {'id': 'job-1', 'status': 'pending'}),
      ]);

      final jobId = await env.api.start([1, 2, 3, 4], 'audio/mp4');

      expect(jobId, 'job-1');
      final request = env.adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/transcriptions');
      expect(request.headers[Headers.contentTypeHeader], 'audio/mp4');
    });
  });

  group('poll', () {
    test('reads the job status', () async {
      final env = apiFor([
        FakeReply(200, body: {'status': 'completed', 'transcript': 'hello'}),
      ]);

      final job = await env.api.poll('job-1');

      expect(job.status, TranscriptionStatus.completed);
      expect(job.transcript, 'hello');
      expect(env.adapter.requests.single.path, '/transcriptions/job-1');
    });
  });

  group('transcribe', () {
    test(
      'starts, polls once, and returns the transcript on completion',
      () async {
        final env = apiFor([
          FakeReply(202, body: {'id': 'job-1', 'status': 'pending'}),
          FakeReply(
            200,
            body: {'status': 'completed', 'transcript': 'hello world'},
          ),
        ]);

        final transcript = await env.api.transcribe(
          [1, 2, 3],
          'audio/mp4',
          delay: noDelay,
        );

        expect(transcript, 'hello world');
        expect(env.adapter.requests, hasLength(2));
      },
    );

    test(
      'a null transcript on completion resolves to an empty string',
      () async {
        final env = apiFor([
          FakeReply(202, body: {'id': 'job-1', 'status': 'pending'}),
          FakeReply(200, body: {'status': 'completed'}),
        ]);

        final transcript = await env.api.transcribe(
          [1],
          'audio/mp4',
          delay: noDelay,
        );

        expect(transcript, '');
      },
    );

    test('polls again while pending, then returns on completion', () async {
      final env = apiFor([
        FakeReply(202, body: {'id': 'job-1', 'status': 'pending'}),
        FakeReply(200, body: {'status': 'pending'}),
        FakeReply(200, body: {'status': 'pending'}),
        FakeReply(200, body: {'status': 'completed', 'transcript': 'done'}),
      ]);

      final transcript = await env.api.transcribe(
        [1],
        'audio/mp4',
        delay: noDelay,
        pollInterval: const Duration(milliseconds: 1),
      );

      expect(transcript, 'done');
      expect(env.adapter.requests, hasLength(4));
    });

    test('a failed job throws NetworkFailure carrying the job error', () async {
      final env = apiFor([
        FakeReply(202, body: {'id': 'job-1', 'status': 'pending'}),
        FakeReply(200, body: {'status': 'failed', 'error': 'model crashed'}),
      ]);

      await expectLater(
        env.api.transcribe([1], 'audio/mp4', delay: noDelay),
        throwsA(
          isA<NetworkFailure>().having(
            (e) => e.message,
            'message',
            'model crashed',
          ),
        ),
      );
    });

    test(
      'a failed job with no error message gets a sensible default',
      () async {
        final env = apiFor([
          FakeReply(202, body: {'id': 'job-1', 'status': 'pending'}),
          FakeReply(200, body: {'status': 'failed'}),
        ]);

        await expectLater(
          env.api.transcribe([1], 'audio/mp4', delay: noDelay),
          throwsA(
            isA<NetworkFailure>().having(
              (e) => e.message,
              'message',
              isNotEmpty,
            ),
          ),
        );
      },
    );

    test('gives up once the timeout elapses, without ever sleeping', () async {
      final env = apiFor([
        FakeReply(202, body: {'id': 'job-1', 'status': 'pending'}),
        FakeReply(200, body: {'status': 'pending'}),
        FakeReply(200, body: {'status': 'pending'}),
      ]);

      await expectLater(
        env.api.transcribe(
          [1],
          'audio/mp4',
          delay: noDelay,
          pollInterval: const Duration(seconds: 1),
          timeout: const Duration(seconds: 2),
        ),
        throwsA(
          isA<NetworkFailure>().having(
            (e) => e.message,
            'message',
            contains('longer than expected'),
          ),
        ),
      );
    });
  });
}
