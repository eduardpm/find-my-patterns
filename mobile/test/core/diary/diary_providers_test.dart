import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/diary/diary_providers.dart';
import 'package:find_my_patterns/core/diary/entries_api.dart';
import 'package:find_my_patterns/core/diary/feelings_api.dart';
import 'package:find_my_patterns/core/diary/guiding_questions_api.dart';
import 'package:find_my_patterns/core/diary/insights_api.dart';
import 'package:find_my_patterns/core/diary/monthly_summary_api.dart';
import 'package:find_my_patterns/core/diary/topics_api.dart';
import 'package:find_my_patterns/core/diary/transcriptions_api.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';

void main() {
  ProviderContainer containerFor(FakeHttpAdapter adapter) {
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter)
      ..configure(const BackendAddress(host: '10.0.2.2'));
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('feelingsApiProvider builds a FeelingsApi over the shared client', () {
    final container = containerFor(FakeHttpAdapter([]));
    expect(container.read(feelingsApiProvider), isA<FeelingsApi>());
  });

  test('guidingQuestionsApiProvider builds a GuidingQuestionsApi', () {
    final container = containerFor(FakeHttpAdapter([]));
    expect(
      container.read(guidingQuestionsApiProvider),
      isA<GuidingQuestionsApi>(),
    );
  });

  test('entriesApiProvider builds an EntriesApi', () {
    final container = containerFor(FakeHttpAdapter([]));
    expect(container.read(entriesApiProvider), isA<EntriesApi>());
  });

  test('insightsApiProvider builds an InsightsApi', () {
    final container = containerFor(FakeHttpAdapter([]));
    expect(container.read(insightsApiProvider), isA<InsightsApi>());
  });

  test('monthlySummaryApiProvider builds a MonthlySummaryApi', () {
    final container = containerFor(FakeHttpAdapter([]));
    expect(container.read(monthlySummaryApiProvider), isA<MonthlySummaryApi>());
  });

  test('topicsApiProvider builds a TopicsApi', () {
    final container = containerFor(FakeHttpAdapter([]));
    expect(container.read(topicsApiProvider), isA<TopicsApi>());
  });

  test('transcriptionsApiProvider builds a TranscriptionsApi', () {
    final container = containerFor(FakeHttpAdapter([]));
    expect(container.read(transcriptionsApiProvider), isA<TranscriptionsApi>());
  });

  test('every api provider is a singleton within a scope', () {
    final container = containerFor(FakeHttpAdapter([]));
    expect(
      container.read(feelingsApiProvider),
      same(container.read(feelingsApiProvider)),
    );
    expect(
      container.read(entriesApiProvider),
      same(container.read(entriesApiProvider)),
    );
  });

  test(
    'feelingCatalogProvider loads the catalog through feelingsApiProvider',
    () async {
      final adapter = FakeHttpAdapter([
        FakeReply(
          200,
          body: {
            'feelings': [
              {
                'key': 'happy',
                'label': 'Happy',
                'valence': 'positive',
                'group_key': 'uplifted',
              },
            ],
          },
        ),
      ]);
      final container = containerFor(adapter);

      final catalog = await container.read(feelingCatalogProvider.future);

      expect(catalog.fromKey('happy')?.label, 'Happy');
    },
  );

  test('guidingQuestionLibraryProvider loads the library through guidingQuestionsApiProvider', () async {
    final adapter = FakeHttpAdapter([
      FakeReply(
        200,
        body: {
          'questions': [
            {
              'key': 'general',
              'category': 'general',
              'prompt_text': 'How was your day?',
            },
          ],
        },
      ),
    ]);
    final container = containerFor(adapter);

    final library = await container.read(guidingQuestionLibraryProvider.future);

    expect(library.single.key, 'general');
  });
}
