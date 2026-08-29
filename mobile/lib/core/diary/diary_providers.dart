import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/network_providers.dart';
import 'entries_api.dart';
import 'experiments_api.dart';
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

/// Starting, reading, and abandoning N-of-1 experiments (R-3a/R-3b).
final experimentsApiProvider = Provider<ExperimentsApi>(
  (ref) => ExperimentsApi(ref.watch(apiClientProvider)),
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

/// A counter [DiaryWriteSignal] bumps whenever a write elsewhere in the app
/// may have changed what a day's entries or its summary look like: the
/// composer finishing a new entry, or entry-detail saving an edit or a
/// delete.
///
/// A screen that reads a day's data listens for this instead of the writer
/// calling back into that screen directly -- the composer and entry-detail
/// don't need to know Today exists, and Calendar or the day view can start
/// listening too without a second wiring on the writing side.
class DiaryWriteSignal extends Notifier<int> {
  @override
  int build() => 0;

  /// Records that a write has happened.
  void bump() => state++;
}

/// The signal Today (and, later, Calendar/day view) listens to for a write
/// made anywhere else in the app.
final diaryWriteSignalProvider = NotifierProvider<DiaryWriteSignal, int>(
  DiaryWriteSignal.new,
);
