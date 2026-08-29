// Test-only builders for the Insights domain types.
//
// `Pattern` and friends take long, strictly-ordered positional argument
// lists (see `lib/core/diary/pattern.dart`) so their real callers -- the
// JSON decoders -- never have to name a field. Tests care about the
// opposite: naming exactly the field under test and leaving everything
// else at a plausible default. These builders translate one into the
// other so a test reads as "a pattern with a null lift", not as a
// twenty-seven-argument tuple.

import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';

/// A feeling with sensible defaults, for tests that need one but do not
/// care about its exact vocabulary.
Feeling buildFeeling({
  String key = 'stressed',
  String label = 'Stressed',
  Valence valence = Valence.negative,
  String groupKey = 'tense',
}) => Feeling(key, label, valence, groupKey);

/// One evidence row behind a pattern.
PatternEvidence buildEvidence({
  String entryId = 'entry-1',
  CalendarDate? entryDate,
  String rawText = 'Long day at work, too much coffee.',
  List<Feeling>? feelings,
  FeelingSource feelingSource = FeelingSource.confirmed,
}) => PatternEvidence(
  entryId,
  entryDate ?? const CalendarDate(2026, 8, 20),
  rawText,
  feelings ?? [buildFeeling()],
  feelingSource,
);

/// A confounder note attached to a pattern.
Confounder buildConfounder({
  String topic = 'work',
  double coOccurrenceRate = 0.6,
  int bothCount = 3,
  int onlyThisCount = 1,
  int onlyOtherCount = 2,
  int neitherCount = 10,
  bool inseparable = false,
  String note = 'Coffee and work often show up together.',
}) => Confounder(
  topic,
  coOccurrenceRate,
  bothCount,
  onlyThisCount,
  onlyOtherCount,
  neitherCount,
  inseparable,
  note,
);

/// R-1: a "Worth trying" recommendation, with defaults that read as a
/// plausible inverse, protective-topic card.
Recommendation buildRecommendation({
  String actionTopic = 'exercise',
  String headline = 'More exercise days',
  String sentence =
      'On days without exercise, anxious is 2.7× more likely '
      '(4 of 6 without vs 1 of 4 with). More exercise days may help — '
      "here's the evidence.",
  String patternRef = 'pattern-1',
}) => Recommendation(actionTopic, headline, sentence, patternRef);

/// A pattern with defaults that read as a plausible "happening now",
/// forward, change-worthy card. Override only what a test is about.
Pattern buildPattern({
  String id = 'pattern-1',
  PatternKind kind = PatternKind.forward,
  String topic = 'coffee',
  Feeling? feeling,
  int occurrenceCount = 4,
  int lifetimeCount = 4,
  PatternStatus status = PatternStatus.active,
  PatternDirection direction = PatternDirection.change,
  String narrativeText = 'Coffee shows up with feeling stressed often.',
  String suggestionText = 'Try skipping coffee on a hard day.',
  int presentCount = 4,
  int presentTotal = 5,
  int absentCount = 6,
  int absentTotal = 25,
  double? presentRate = 0.8,
  double? absentRate = 0.24,
  double baseRate = 0.33,
  double? lift = 2.4,
  String? comparisonReason,
  String? comparisonNote,
  bool isStrong = false,
  CalendarDate? lastOccurrenceDate,
  int? daysSinceLastOccurrence,
  String? historicalNote,
  List<Confounder> confounders = const [],
  List<PatternEvidence> evidence = const [],
  DateTime? lastUpdatedAt,
  Recommendation? recommendation,
}) => Pattern(
  id,
  kind,
  topic,
  feeling ?? buildFeeling(),
  occurrenceCount,
  lifetimeCount,
  status,
  direction,
  narrativeText,
  suggestionText,
  presentCount,
  presentTotal,
  absentCount,
  absentTotal,
  presentRate,
  absentRate,
  baseRate,
  lift,
  comparisonReason,
  comparisonNote,
  isStrong,
  lastOccurrenceDate,
  daysSinceLastOccurrence,
  historicalNote,
  confounders,
  evidence,
  lastUpdatedAt ?? DateTime.utc(2026, 8, 20),
  recommendation,
);

/// A withdrawal notice with plausible defaults.
Withdrawal buildWithdrawal({
  String id = 'withdrawal-1',
  String topic = 'coffee',
  String feeling = 'stressed',
  PatternKind kind = PatternKind.forward,
  int previousCount = 5,
  int newCount = 1,
  WithdrawalReason reason = WithdrawalReason.belowThreshold,
  String detailText = 'Only 1 of the last 5 occurrences held.',
  DateTime? withdrawnAt,
  bool isNew = true,
}) => Withdrawal(
  id,
  topic,
  feeling,
  kind,
  previousCount,
  newCount,
  reason,
  detailText,
  withdrawnAt ?? DateTime.utc(2026, 8, 18),
  isNew,
);

/// The engine's thresholds, defaulting to [EngineConstants.placeholder].
EngineConstants buildConstants({
  int minOccurrenceThreshold = 3,
  int recencyWindowDays = 30,
  double minLift = 1.5,
  double strongLift = 3,
  int strongMinOccurrences = 5,
  int minComparisonEntries = 3,
  double collinearityThreshold = 0.8,
  int minBucketEntries = 3,
  int minIntensity = 1,
  int maxIntensity = 5,
}) => EngineConstants(
  minOccurrenceThreshold,
  recencyWindowDays,
  minLift,
  strongLift,
  strongMinOccurrences,
  minComparisonEntries,
  collinearityThreshold,
  minBucketEntries,
  minIntensity,
  maxIntensity,
);

/// One weekday/time-of-day bucket.
WhenBucket buildBucket({
  String key = 'monday',
  String label = 'Monday',
  int entryCount = 5,
  double? averageValence = 0.2,
  double? negativeRate = 0.3,
  bool sufficient = true,
}) => WhenBucket(
  key,
  label,
  entryCount,
  averageValence,
  negativeRate,
  sufficient,
);

/// The "when" panel's data, with one weekday and one time-of-day bucket by
/// default.
///
/// [hourly] defaults to an empty list, not a populated one -- the same
/// default an old backend that predates CH-5 decodes to (see
/// `whenInsightsFromJson`) -- so every test written before the heat strip
/// existed keeps exercising exactly the widget tree it always has, and only
/// a test that explicitly passes [hourly] sees the strip at all.
WhenInsights buildWhenInsights({
  int windowDays = 30,
  int minBucketEntries = 3,
  int totalEntries = 12,
  List<WhenBucket>? weekdays,
  List<WhenBucket>? timesOfDay,
  String? bestWeekday,
  String? worstWeekday,
  String? bestTimeOfDay,
  String? worstTimeOfDay,
  List<WhenBucket>? hourly,
  String? bestHour,
  String? worstHour,
  String? busiestTimeOfDay,
}) => WhenInsights(
  windowDays,
  minBucketEntries,
  totalEntries,
  weekdays ?? [buildBucket()],
  timesOfDay ?? [buildBucket(key: 'evening', label: 'Evening')],
  bestWeekday,
  worstWeekday,
  bestTimeOfDay,
  worstTimeOfDay,
  hourly ?? const [],
  bestHour,
  worstHour,
  busiestTimeOfDay,
);

/// Twelve hourly buckets keyed `00`, `02`, … `22`, all sufficient with a
/// mild positive average by default -- a plausible "nothing suppressed, no
/// standout hour" heat strip a test can override just the cells it cares
/// about.
List<WhenBucket> buildHourlyBuckets({
  Map<String, WhenBucket> overrides = const {},
}) => [
  for (var hour = 0; hour < 24; hour += 2)
    overrides[hour.toString().padLeft(2, '0')] ??
        buildBucket(
          key: hour.toString().padLeft(2, '0'),
          label:
              '${hour.toString().padLeft(2, '0')}:00–'
              '${((hour + 2) % 24).toString().padLeft(2, '0')}:00',
          entryCount: 5,
          averageValence: 0.1,
          negativeRate: 0.2,
        ),
];
