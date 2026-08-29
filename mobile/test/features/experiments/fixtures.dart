// Test-only builders for the experiments domain types (R-3a/R-3b). See
// `test/features/insights/fixtures.dart` for the identical reasoning: the
// real model types take long, strictly-ordered positional argument lists so
// their JSON decoders never have to name a field, and these translate that
// into "an experiment with a null activeExperiment", not a tuple.

import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/experiment.dart';

/// The experiments engine's thresholds and defaults, with sensible
/// defaults matching the backend's own (`experiments/constants.ts`).
ExperimentConstants buildExperimentConstants({
  int defaultLengthDays = 7,
  int minLengthDays = 7,
  int maxLengthDays = 28,
  int minBucketEntries = 3,
}) => ExperimentConstants(
  defaultLengthDays,
  minLengthDays,
  maxLengthDays,
  minBucketEntries,
);

/// An experiment with plausible defaults: active, seven days, starting
/// today. Override only what a test is about.
Experiment buildExperiment({
  String id = 'experiment-1',
  String patternTopic = 'exercise',
  String patternFeeling = 'exhausted',
  HypothesisKind hypothesisKind = HypothesisKind.moreOf,
  CalendarDate? startDate,
  CalendarDate? endDate,
  ExperimentStatus status = ExperimentStatus.active,
  DateTime? createdAt,
  ExperimentConstants? constants,
}) => Experiment(
  id,
  patternTopic,
  patternFeeling,
  hypothesisKind,
  startDate ?? const CalendarDate(2026, 8, 1),
  endDate ?? const CalendarDate(2026, 8, 7),
  status,
  createdAt ?? DateTime.utc(2026, 8, 1),
  constants ?? buildExperimentConstants(),
);

/// One window of a results comparison, with plausible defaults.
ExperimentWindow buildExperimentWindow({
  CalendarDate? startDate,
  CalendarDate? endDate,
  int totalDays = 7,
  int daysWithTopic = 4,
  int presentCount = 1,
  int presentTotal = 4,
  int absentCount = 1,
  int absentTotal = 2,
  double? presentRate = 0.25,
  double? absentRate = 0.5,
}) => ExperimentWindow(
  startDate ?? const CalendarDate(2026, 8, 1),
  endDate ?? const CalendarDate(2026, 8, 7),
  totalDays,
  daysWithTopic,
  presentCount,
  presentTotal,
  absentCount,
  absentTotal,
  presentRate,
  absentRate,
);

/// A results payload with plausible defaults: a clear-looking difference
/// between the two windows, well above the suppression floor. Override
/// [experimentWindow], [baselineWindow], [verdictText] and
/// [insufficientData] together for the "no difference" or
/// "insufficient data" cases.
ExperimentResults buildExperimentResults({
  Experiment? experiment,
  ExperimentWindow? experimentWindow,
  ExperimentWindow? baselineWindow,
  String verdictText =
      'During the experiment you mentioned exercise on 4 '
      'of 7 days; exhausted appeared in 1 of 4 entries (25%) vs 3 of 5 '
      '(60%) in the 7 days before.',
  bool insufficientData = false,
  ExperimentConstants? constants,
}) => ExperimentResults(
  experiment ?? buildExperiment(),
  experimentWindow ?? buildExperimentWindow(),
  baselineWindow ??
      buildExperimentWindow(
        startDate: const CalendarDate(2026, 7, 25),
        endDate: const CalendarDate(2026, 7, 31),
        daysWithTopic: 5,
        presentCount: 3,
        presentTotal: 5,
        presentRate: 0.6,
      ),
  verdictText,
  insufficientData,
  constants ?? buildExperimentConstants(),
);
