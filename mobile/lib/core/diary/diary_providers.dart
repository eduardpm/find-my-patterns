import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/network_providers.dart';
import 'entries_api.dart';
import 'feeling.dart';
import 'feelings_api.dart';
import 'guiding_question.dart';
import 'guiding_questions_api.dart';
import 'insights_api.dart';
import 'monthly_summary_api.dart';
import 'topics_api.dart';
import 'transcriptions_api.dart';

/// The feeling vocabulary the composer offers.
final feelingsApiProvider = Provider<FeelingsApi>(
  (ref) => FeelingsApi(ref.watch(apiClientProvider)),
);

/// The guiding-question library the guided flow walks.
final guidingQuestionsApiProvider = Provider<GuidingQuestionsApi>(
  (ref) => GuidingQuestionsApi(ref.watch(apiClientProvider)),
);

/// Creating, reading, editing and deleting diary entries.
final entriesApiProvider = Provider<EntriesApi>(
  (ref) =>
      EntriesApi(ref.watch(apiClientProvider), ref.watch(feelingsApiProvider)),
);

/// The detected patterns shown on Insights.
final insightsApiProvider = Provider<InsightsApi>(
  (ref) =>
      InsightsApi(ref.watch(apiClientProvider), ref.watch(feelingsApiProvider)),
);

/// A month's worth of entry density, for the calendar.
final monthlySummaryApiProvider = Provider<MonthlySummaryApi>(
  (ref) => MonthlySummaryApi(
    ref.watch(apiClientProvider),
    ref.watch(feelingsApiProvider),
  ),
);

/// The canonical topics and their aliases.
final topicsApiProvider = Provider<TopicsApi>(
  (ref) => TopicsApi(ref.watch(apiClientProvider)),
);

/// Uploading a recording and polling for its transcript.
final transcriptionsApiProvider = Provider<TranscriptionsApi>(
  (ref) => TranscriptionsApi(ref.watch(apiClientProvider)),
);

/// The feeling vocabulary, loaded once and shared by every screen that needs
/// to resolve or offer a feeling.
///
/// A thin wrapper over [FeelingsApi.catalog] so a screen can `ref.watch`
/// this instead of reaching into the API layer itself.
final feelingCatalogProvider = FutureProvider<FeelingCatalog>(
  (ref) => ref.watch(feelingsApiProvider).catalog(),
);

/// The guiding-question library, loaded once and shared by every screen that
/// needs to lay out or match against it.
final guidingQuestionLibraryProvider = FutureProvider<List<GuidingQuestion>>(
  (ref) => ref.watch(guidingQuestionsApiProvider).library(),
);
