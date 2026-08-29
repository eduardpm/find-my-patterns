// Wire-shaped JSON fixtures for the endpoints behind Insights:
// `GET /feelings`, `GET /insights`, `GET /insights/when`, and the
// withdrawal-acknowledgement `POST`. Field names are snake_case, matching
// what `lib/core/diary/pattern.dart` and `feelings_api.dart` decode.

/// The feeling catalog `InsightsApi.insights()` resolves feeling keys
/// through before it can decode a single pattern.
Map<String, Object?> feelingsCatalogJson() => {
  'feelings': [
    {
      'key': 'stressed',
      'label': 'Stressed',
      'valence': 'negative',
      'group_key': 'tense',
    },
    {
      'key': 'happy',
      'label': 'Happy',
      'valence': 'positive',
      'group_key': 'uplifted',
    },
  ],
  'groups': <Object?>[],
};

/// One pattern in `GET /insights`'s `patterns` array.
Map<String, Object?> patternJson({
  String id = 'pattern-1',
  String kind = 'forward',
  String topic = 'coffee',
  String? feeling = 'stressed',
  int occurrenceCount = 4,
  int lifetimeCount = 4,
  String status = 'active',
  String direction = 'change',
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
  bool isStrong = false,
  String? historicalNote,
  List<Map<String, Object?>> evidence = const [],
}) => {
  'id': id,
  'kind': kind,
  'topic': topic,
  'feeling': feeling,
  'occurrence_count': occurrenceCount,
  'lifetime_count': lifetimeCount,
  'status': status,
  'direction': direction,
  'narrative_text': narrativeText,
  'suggestion_text': suggestionText,
  'present_count': presentCount,
  'present_total': presentTotal,
  'absent_count': absentCount,
  'absent_total': absentTotal,
  'present_rate': presentRate,
  'absent_rate': absentRate,
  'base_rate': baseRate,
  'lift': lift,
  'is_strong': isStrong,
  'historical_note': historicalNote,
  'confounders': <Object?>[],
  'evidence': evidence,
  'last_updated_at': '2026-08-20T10:00:00Z',
};

/// One withdrawal in `GET /insights`'s `withdrawals` array.
Map<String, Object?> withdrawalJson({
  String id = 'withdrawal-1',
  String topic = 'coffee',
  String feeling = 'stressed',
  String kind = 'forward',
  int previousCount = 5,
  int newCount = 1,
  String reason = 'below_threshold',
  String detailText = 'Only 1 of the last 5 occurrences held.',
  bool isNew = true,
}) => {
  'id': id,
  'topic': topic,
  'feeling': feeling,
  'kind': kind,
  'previous_count': previousCount,
  'new_count': newCount,
  'reason': reason,
  'detail_text': detailText,
  'withdrawn_at': '2026-08-18T10:00:00Z',
  'is_new': isNew,
};

Map<String, Object?> _constantsJson() => {
  'min_occurrence_threshold': 3,
  'recency_window_days': 30,
  'min_lift': 1.5,
  'strong_lift': 3.0,
  'strong_min_occurrences': 5,
  'min_comparison_entries': 3,
  'collinearity_threshold': 0.8,
  'min_bucket_entries': 3,
  'min_intensity': 1,
  'max_intensity': 5,
};

/// `GET /insights`'s whole response.
Map<String, Object?> insightsResultJson({
  List<Map<String, Object?>> patterns = const [],
  List<Map<String, Object?>> withdrawals = const [],
  int newWithdrawalCount = 0,
  bool insufficientData = false,
}) => {
  'patterns': patterns,
  'withdrawals': withdrawals,
  'new_withdrawal_count': newWithdrawalCount,
  'insufficient_data': insufficientData,
  'constants': _constantsJson(),
};

/// One bucket in `GET /insights/when`'s `weekdays`/`times_of_day` arrays.
Map<String, Object?> bucketJson({
  String key = 'monday',
  String label = 'Monday',
  int entryCount = 5,
  double? averageValence = 0.2,
  double? negativeRate = 0.3,
  bool sufficient = true,
}) => {
  'key': key,
  'label': label,
  'entry_count': entryCount,
  'average_valence': averageValence,
  'negative_rate': negativeRate,
  'sufficient': sufficient,
};

/// One point in `GET /insights/series`'s `points` array.
Map<String, Object?> seriesPointJson({
  String date = '2026-08-25',
  double? score = 0.2,
  int entryCount = 1,
  int confirmedFeelingCount = 1,
}) => {
  'date': date,
  'score': score,
  'entry_count': entryCount,
  'confirmed_feeling_count': confirmedFeelingCount,
};

/// `GET /insights/series`'s whole response. Empty by default: the
/// mood-trend chart's own empty state is what most screen-level tests want,
/// since they are not about the chart.
Map<String, Object?> seriesJson({
  List<Map<String, Object?>> points = const [],
}) => {'granularity': 'day', 'points': points, 'constants': _constantsJson()};

/// `GET /insights/when`'s whole response.
Map<String, Object?> whenInsightsJson({
  int totalEntries = 12,
  List<Map<String, Object?>>? weekdays,
  List<Map<String, Object?>>? timesOfDay,
}) => {
  'window_days': 30,
  'min_bucket_entries': 3,
  'total_entries': totalEntries,
  'weekdays': weekdays ?? [bucketJson()],
  'times_of_day': timesOfDay ?? [bucketJson(key: 'evening', label: 'Evening')],
  'best_weekday': null,
  'worst_weekday': null,
  'best_time_of_day': null,
  'worst_time_of_day': null,
};
