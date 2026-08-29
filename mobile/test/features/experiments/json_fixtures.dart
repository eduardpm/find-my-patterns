// Wire-shaped JSON fixtures for the experiments endpoints (R-3a): `POST
// /experiments`, `GET /experiments/active`, `POST /experiments/{id}/abandon`
// and `GET /experiments/{id}/results`. Field names are snake_case, matching
// what `lib/core/diary/experiment.dart` decodes.

Map<String, Object?> experimentConstantsJson({
  int defaultLengthDays = 7,
  int minLengthDays = 7,
  int maxLengthDays = 28,
  int minBucketEntries = 3,
}) => {
  'default_length_days': defaultLengthDays,
  'min_length_days': minLengthDays,
  'max_length_days': maxLengthDays,
  'min_bucket_entries': minBucketEntries,
};

/// One experiment, as every experiments endpoint but `results` returns it
/// directly (and `results` nests it under `experiment`).
Map<String, Object?> experimentJson({
  String id = 'experiment-1',
  String patternTopic = 'exercise',
  String patternFeeling = 'exhausted',
  String hypothesisKind = 'more_of',
  String startDate = '2026-08-01',
  String endDate = '2026-08-07',
  String status = 'active',
}) => {
  'id': id,
  'pattern_topic': patternTopic,
  'pattern_feeling': patternFeeling,
  'hypothesis_kind': hypothesisKind,
  'start_date': startDate,
  'end_date': endDate,
  'status': status,
  'created_at': '2026-08-01T09:00:00Z',
  'constants': experimentConstantsJson(),
};

/// `GET /experiments/active`'s 404 body -- nothing running.
Map<String, Object?> noActiveExperimentErrorJson() => {
  'error': {
    'code': 'not_found',
    'message': 'No experiment is currently active.',
  },
};

/// A `POST /experiments` 422 rejection body.
Map<String, Object?> experimentValidationErrorJson({
  String message = 'This pattern is not currently qualifying.',
}) => {
  'error': {'code': 'validation_error', 'message': message},
};

/// One results window (`experiment_window` or `baseline_window`).
Map<String, Object?> experimentWindowJson({
  String startDate = '2026-08-01',
  String endDate = '2026-08-07',
  int totalDays = 7,
  int daysWithTopic = 4,
  int presentCount = 1,
  int presentTotal = 4,
  int absentCount = 1,
  int absentTotal = 2,
  double? presentRate = 0.25,
  double? absentRate = 0.5,
}) => {
  'start_date': startDate,
  'end_date': endDate,
  'total_days': totalDays,
  'days_with_topic': daysWithTopic,
  'present_count': presentCount,
  'present_total': presentTotal,
  'absent_count': absentCount,
  'absent_total': absentTotal,
  'present_rate': presentRate,
  'absent_rate': absentRate,
};

/// `GET /experiments/{id}/results`'s whole response.
Map<String, Object?> experimentResultsJson({
  Map<String, Object?>? experiment,
  Map<String, Object?>? experimentWindow,
  Map<String, Object?>? baselineWindow,
  String verdictText =
      'During the experiment you mentioned exercise on 4 '
      'of 7 days; exhausted appeared in 1 of 4 entries (25%) vs 3 of 5 '
      '(60%) in the 7 days before.',
  bool insufficientData = false,
}) => {
  'experiment': experiment ?? experimentJson(status: 'finished'),
  'experiment_window': experimentWindow ?? experimentWindowJson(),
  'baseline_window':
      baselineWindow ??
      experimentWindowJson(
        startDate: '2026-07-25',
        endDate: '2026-07-31',
        daysWithTopic: 5,
        presentCount: 3,
        presentTotal: 5,
        presentRate: 0.6,
      ),
  'verdict_text': verdictText,
  'insufficient_data': insufficientData,
  'constants': experimentConstantsJson(),
};
