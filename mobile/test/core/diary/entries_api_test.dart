import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entries_api.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/feelings_api.dart';
import 'package:find_my_patterns/core/diary/guiding_question.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/network/api_error.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';

void main() {
  const happy = Feeling('happy', 'Happy', Valence.positive, 'uplifted');
  const sad = Feeling('sad', 'Sad', Valence.negative, 'low');
  final catalog = FeelingCatalog([happy, sad]);

  final feelingsBody = {
    'feelings': [
      {
        'key': 'happy',
        'label': 'Happy',
        'valence': 'positive',
        'group_key': 'uplifted',
      },
      {'key': 'sad', 'label': 'Sad', 'valence': 'negative', 'group_key': 'low'},
    ],
  };

  ApiClient clientFor(FakeHttpAdapter adapter) {
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
    client.configure(const BackendAddress(host: '10.0.2.2'));
    return client;
  }

  ({EntriesApi api, FakeHttpAdapter adapter}) apiFor(List<FakeReply> replies) {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsBody),
      ...replies,
    ]);
    final client = clientFor(adapter);
    final api = EntriesApi(client, FeelingsApi(client));
    return (api: api, adapter: adapter);
  }

  Map<String, Object?> entryJson({
    String id = 'entry-1',
    String feelingKey = 'happy',
    int version = 4,
  }) => {
    'id': id,
    'created_at': '2026-07-28T13:05:00Z',
    'entry_date': '2026-07-28',
    'mode': 'freeform',
    'raw_text': 'a day',
    'feeling_key': feelingKey,
    'feeling_keys': [feelingKey],
    'feeling_source': 'confirmed',
    'version': version,
  };

  group('createFreeform', () {
    test('posts the text under freeform mode', () async {
      final env = apiFor([FakeReply(201, body: entryJson())]);
      final entry = await env.api.createFreeform('my day');

      expect(entry.id, 'entry-1');
      final request = env.adapter.requests.last;
      expect(request.method, 'POST');
      expect(request.path, '/entries');
      expect(request.data, {'mode': 'freeform', 'raw_text': 'my day'});
    });
  });

  group('createGuided', () {
    test('posts the answers with an empty raw_text', () async {
      final env = apiFor([FakeReply(201, body: entryJson())]);
      await env.api.createGuided([
        const GuidingQuestionAnswer('q1', 'Good.'),
      ]);

      final request = env.adapter.requests.last;
      expect(request.data, {
        'mode': 'guided',
        'raw_text': '',
        'guided_answers': [
          {'question_key': 'q1', 'answer_text': 'Good.'},
        ],
      });
    });
  });

  group('listByDate', () {
    test('reads the date-filtered list', () async {
      final env = apiFor([
        FakeReply(
          200,
          body: {
            'entries': [entryJson(), entryJson(id: 'entry-2')],
          },
        ),
      ]);

      final entries = await env.api.listByDate(const CalendarDate(2026, 7, 28));

      expect(entries.map((e) => e.id), ['entry-1', 'entry-2']);
      expect(env.adapter.requests.last.uri.path, '/entries');
      expect(
        env.adapter.requests.last.uri.queryParameters['date'],
        '2026-07-28',
      );
    });
  });

  group('getById', () {
    test('reads one entry', () async {
      final env = apiFor([FakeReply(200, body: entryJson())]);
      final entry = await env.api.getById('entry-1');
      expect(entry.id, 'entry-1');
      expect(env.adapter.requests.last.path, '/entries/entry-1');
    });
  });

  group('echo', () {
    test('reads the pattern echoes for an entry', () async {
      // echo does not need the feeling catalog -- PatternEcho.feeling is a
      // bare wire string, not resolved through it -- so, unlike every other
      // method here, it issues exactly one request and needs no feelings
      // reply queued ahead of it.
      final adapter = FakeHttpAdapter([
        FakeReply(
          200,
          body: {
            'echoes': [
              {
                'pattern_id': 'p1',
                'topic': 'meetings',
                'feeling': 'anxious',
                'occurrence_count': 8,
                'present_count': 8,
                'present_total': 12,
                'lift': 6.2,
                'narrative_text': 'narrative',
              },
            ],
          },
        ),
      ]);
      final client = clientFor(adapter);
      final api = EntriesApi(client, FeelingsApi(client));

      final echoes = await api.echo('entry-1');

      expect(echoes.single.patternId, 'p1');
      expect(adapter.requests.single.path, '/entries/entry-1/echo');
    });
  });

  group('deleteById', () {
    test(
      'sends the version as a query parameter and returns EntryRemoved',
      () async {
        final env = apiFor([FakeReply(204)]);
        final result = await env.api.deleteById(id: 'entry-1', version: 9);

        expect(result, isA<EntryRemoved>());
        final request = env.adapter.requests.last;
        expect(request.method, 'DELETE');
        expect(request.uri.path, '/entries/entry-1');
        expect(request.uri.queryParameters['version'], '9');
      },
    );

    final staleBody = {
      'error': {
        'code': 'stale_entry',
        'message': 'This entry was changed somewhere else since you loaded it.',
      },
      'current': entryJson(version: 6),
    };

    test('a 409 becomes EntryOutOfDate carrying the parsed current entry, and nothing is reported deleted', () async {
      final env = apiFor([FakeReply(409, body: staleBody)]);
      final result = await env.api.deleteById(id: 'entry-1', version: 2);

      expect(result, isNot(isA<EntryRemoved>()));
      final outOfDate = result as EntryOutOfDate;
      expect(
        outOfDate.message,
        'This entry was changed somewhere else since you loaded it.',
      );
      expect(outOfDate.current.id, 'entry-1');
      expect(outOfDate.current.version, 6);
    });

    test(
      'the stale current entry resolves its feeling through the catalog',
      () async {
        final env = apiFor([FakeReply(409, body: staleBody)]);
        final result = await env.api.deleteById(id: 'entry-1', version: 2);
        final outOfDate = result as EntryOutOfDate;
        expect(outOfDate.current.feeling, happy);
      },
    );

    test('a 409 whose body cannot be decoded still fails, without inventing a current entry', () async {
      final env = apiFor([FakeReply(409, body: 'not an object')]);
      await expectLater(
        env.api.deleteById(id: 'entry-1', version: 2),
        throwsA(isA<HttpFailure>()),
      );
    });

    test(
      'a stale-entry result is distinguishable from a generic server error',
      () async {
        final conflictEnv = apiFor([FakeReply(409, body: staleBody)]);
        final conflict = await conflictEnv.api.deleteById(
          id: 'entry-1',
          version: 2,
        );
        expect(conflict, isA<EntryOutOfDate>());

        final errorEnv = apiFor([
          FakeReply(
            500,
            body: {
              'error': {'code': 'error', 'message': 'boom'},
            },
          ),
        ]);
        await expectLater(
          errorEnv.api.deleteById(id: 'entry-1', version: 2),
          throwsA(
            isA<HttpFailure>().having((e) => e.statusCode, 'statusCode', 500),
          ),
        );
      },
    );
  });

  group('buildUpdateBody', () {
    test('version is always sent even with nothing else', () {
      expect(buildUpdateBody(version: 9), {'version': 9});
    });

    test('raw_text is included only when text is given', () {
      expect(buildUpdateBody(version: 4, text: 'edited'), {
        'version': 4,
        'raw_text': 'edited',
      });
    });

    test('a non-empty feelings list is sent as feeling_keys, in order', () {
      expect(buildUpdateBody(version: 4, feelings: [sad, happy]), {
        'version': 4,
        'feeling_keys': ['sad', 'happy'],
      });
    });

    test('an empty feelings list is omitted rather than sent as []', () {
      final body = buildUpdateBody(
        version: 4,
        text: 'edited',
        feelings: const [],
      );
      expect(body.containsKey('feeling_keys'), isFalse);
      expect(body['raw_text'], 'edited');
    });

    test('intensities absent from the call leaves the field out entirely', () {
      final body = buildUpdateBody(version: 4, text: 'edited');
      expect(body.containsKey('feeling_intensities'), isFalse);
    });

    test('an empty intensities map is still sent, clearing every rating', () {
      expect(buildUpdateBody(version: 4, intensities: const {}), {
        'version': 4,
        'feeling_intensities': <String, int>{},
      });
    });

    test('intensities replace the stored map when given', () {
      expect(buildUpdateBody(version: 4, intensities: const {'happy': 3}), {
        'version': 4,
        'feeling_intensities': {'happy': 3},
      });
    });

    test('never sends the legacy scalar feeling_intensity', () {
      final body = buildUpdateBody(
        version: 4,
        feelings: [happy],
        intensities: const {'happy': 3},
      );
      expect(body.containsKey('feeling_intensity'), isFalse);
    });
  });

  group('entryMutationFromConflict', () {
    final staleBody = {
      'error': {'code': 'stale_entry', 'message': 'Out of date'},
      'current': entryJson(version: 6),
    };

    test('parses a well-formed conflict body into EntryOutOfDate', () {
      final mutation = entryMutationFromConflict(staleBody, catalog);
      expect(mutation, isA<EntryOutOfDate>());
      expect(mutation!.current.version, 6);
      expect(mutation.message, 'Out of date');
    });

    test('returns null for a body that is not the stale-entry shape', () {
      expect(entryMutationFromConflict('not an object', catalog), isNull);
      expect(entryMutationFromConflict(null, catalog), isNull);
      expect(entryMutationFromConflict({'error': 'boom'}, catalog), isNull);
    });
  });

  group('update', () {
    test('sends PATCH with the built body and returns EntryUpdated', () async {
      final env = apiFor([FakeReply(200, body: entryJson())]);
      final result = await env.api.update(
        id: 'entry-1',
        version: 4,
        text: 'edited',
      );

      expect(result, isA<EntryUpdated>());
      expect((result as EntryUpdated).entry.id, 'entry-1');
      final request = env.adapter.requests.last;
      expect(request.method, 'PATCH');
      expect(request.path, '/entries/entry-1');
      expect(request.data, {'version': 4, 'raw_text': 'edited'});
    });

    test('version is always sent even with nothing else', () async {
      final env = apiFor([FakeReply(200, body: entryJson())]);
      await env.api.update(id: 'entry-1', version: 9);
      expect(env.adapter.requests.last.data, {'version': 9});
    });

    test(
      'a non-empty feelings list is sent as feeling_keys, in order',
      () async {
        final env = apiFor([FakeReply(200, body: entryJson())]);
        await env.api.update(id: 'entry-1', version: 4, feelings: [sad, happy]);
        expect(env.adapter.requests.last.data, {
          'version': 4,
          'feeling_keys': ['sad', 'happy'],
        });
      },
    );

    test('an empty feelings list is omitted, not sent as []', () async {
      final env = apiFor([FakeReply(200, body: entryJson())]);
      await env.api.update(
        id: 'entry-1',
        version: 4,
        text: 'edited',
        feelings: const [],
      );
      final data = env.adapter.requests.last.data as Map<String, Object?>;
      expect(data.containsKey('feeling_keys'), isFalse);
      expect(data['raw_text'], 'edited');
    });

    test('intensities left out of the call are left out of the body', () async {
      final env = apiFor([FakeReply(200, body: entryJson())]);
      await env.api.update(id: 'entry-1', version: 4, text: 'edited');
      final data = env.adapter.requests.last.data as Map<String, Object?>;
      expect(data.containsKey('feeling_intensities'), isFalse);
    });

    test(
      'an explicit empty intensities map is sent, clearing every rating',
      () async {
        final env = apiFor([FakeReply(200, body: entryJson())]);
        await env.api.update(id: 'entry-1', version: 4, intensities: const {});
        expect(env.adapter.requests.last.data, {
          'version': 4,
          'feeling_intensities': <String, int>{},
        });
      },
    );

    final staleBody = {
      'error': {'code': 'stale_entry', 'message': 'Out of date'},
      'current': entryJson(version: 6),
    };

    test(
      'a 409 becomes EntryOutOfDate carrying the parsed current entry',
      () async {
        final env = apiFor([FakeReply(409, body: staleBody)]);
        final result = await env.api.update(
          id: 'entry-1',
          version: 2,
          text: 'x',
        );

        final outOfDate = result as EntryOutOfDate;
        expect(outOfDate.message, 'Out of date');
        expect(outOfDate.current.version, 6);
        expect(outOfDate.current.feeling, happy);
      },
    );

    test(
      'a 409 whose body cannot be decoded rethrows as HttpFailure',
      () async {
        final env = apiFor([FakeReply(409, body: 'not an object')]);
        await expectLater(
          env.api.update(id: 'entry-1', version: 2, text: 'x'),
          throwsA(isA<HttpFailure>()),
        );
      },
    );

    test('every other status keeps throwing', () async {
      final env = apiFor([
        FakeReply(
          500,
          body: {
            'error': {'code': 'error', 'message': 'boom'},
          },
        ),
      ]);
      await expectLater(
        env.api.update(id: 'entry-1', version: 2, text: 'x'),
        throwsA(
          isA<HttpFailure>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });
  });

  group('confirmFeelings', () {
    test('sends version, feeling_keys and intensities, no raw_text', () async {
      final env = apiFor([FakeReply(200, body: entryJson())]);
      final result = await env.api.confirmFeelings(
        id: 'entry-1',
        version: 4,
        feelings: [happy],
        intensities: const {'happy': 4},
      );

      expect(result, isA<EntryUpdated>());
      final data = env.adapter.requests.last.data as Map<String, Object?>;
      expect(data, {
        'version': 4,
        'feeling_keys': ['happy'],
        'feeling_intensities': {'happy': 4},
      });
      expect(data.containsKey('raw_text'), isFalse);
    });

    test('a 409 becomes EntryOutOfDate, same as update', () async {
      final env = apiFor([
        FakeReply(
          409,
          body: {
            'error': {'code': 'stale_entry', 'message': 'Out of date'},
            'current': entryJson(version: 6),
          },
        ),
      ]);
      final result = await env.api.confirmFeelings(
        id: 'entry-1',
        version: 2,
        feelings: [happy],
      );
      expect(result, isA<EntryOutOfDate>());
    });
  });
}
