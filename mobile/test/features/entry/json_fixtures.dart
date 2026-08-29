// Wire-shaped JSON fixtures for the endpoints behind the entry-detail
// screen: `GET /feelings`, `GET /entries/{id}`, `PATCH /entries/{id}`,
// `DELETE /entries/{id}`, `GET /entries/{id}/echo`, `GET /insights`. Field
// names are snake_case, matching what `lib/core/diary` decodes.

/// The feeling catalog every one of these endpoints resolves feeling keys
/// through, grouped the way the picker's first level needs.
Map<String, Object?> feelingsCatalogJson() => {
  'feelings': [
    {
      'key': 'happy',
      'label': 'Happy',
      'valence': 'positive',
      'group_key': 'uplifted',
    },
    {
      'key': 'sad',
      'label': 'Sad',
      'valence': 'negative',
      'group_key': 'low',
    },
    {
      'key': 'anxious',
      'label': 'Anxious',
      'valence': 'negative',
      'group_key': 'tense',
    },
  ],
  'groups': [
    {
      'key': 'uplifted',
      'label': 'Uplifted',
      'valence': 'positive',
      'feelings': [
        {
          'key': 'happy',
          'label': 'Happy',
          'valence': 'positive',
          'group_key': 'uplifted',
        },
      ],
    },
    {
      'key': 'low',
      'label': 'Low',
      'valence': 'negative',
      'feelings': [
        {
          'key': 'sad',
          'label': 'Sad',
          'valence': 'negative',
          'group_key': 'low',
        },
      ],
    },
    {
      'key': 'tense',
      'label': 'Tense',
      'valence': 'negative',
      'feelings': [
        {
          'key': 'anxious',
          'label': 'Anxious',
          'valence': 'negative',
          'group_key': 'tense',
        },
      ],
    },
  ],
};

/// `GET /insights`'s whole response, with just enough shape to decode.
Map<String, Object?> insightsJson({int maxIntensity = 5}) => {
  'patterns': <Object?>[],
  'withdrawals': <Object?>[],
  'new_withdrawal_count': 0,
  'insufficient_data': false,
  'constants': {
    'min_occurrence_threshold': 3,
    'recency_window_days': 30,
    'min_lift': 1.5,
    'strong_lift': 3.0,
    'strong_min_occurrences': 5,
    'min_comparison_entries': 3,
    'collinearity_threshold': 0.8,
    'min_bucket_entries': 3,
    'min_intensity': 1,
    'max_intensity': maxIntensity,
  },
};

/// One echo in `GET /entries/{id}/echo`'s `echoes` array.
Map<String, Object?> echoJson({
  String patternId = 'pattern-1',
  String topic = 'coffee',
  String feeling = 'anxious',
}) => {
  'pattern_id': patternId,
  'topic': topic,
  'feeling': feeling,
  'occurrence_count': 4,
  'present_count': 4,
  'present_total': 5,
  'lift': 2.4,
  'narrative_text': 'Coffee shows up with feeling $feeling often.',
};

/// One entry, as `GET /entries/{id}` and `PATCH /entries/{id}` both shape
/// it.
Map<String, Object?> entryJson({
  String id = 'entry-1',
  String createdAt = '2026-08-05T09:00:00Z',
  String entryDate = '2026-08-05',
  String mode = 'freeform',
  String rawText = 'A day.',
  String? feelingKey = 'happy',
  List<String>? feelingKeys,
  String feelingSource = 'confirmed',
  Map<String, int> feelingIntensities = const {},
  List<Map<String, Object?>>? guidedAnswers,
  List<Map<String, Object?>> suggestedFeelings = const [],
  int version = 1,
  bool analysisPending = false,
}) => {
  'id': id,
  'created_at': createdAt,
  'entry_date': entryDate,
  'mode': mode,
  'raw_text': rawText,
  'feeling_key': feelingKey,
  'feeling_keys': feelingKeys ?? [?feelingKey],
  'feeling_source': feelingSource,
  'feeling_intensities': feelingIntensities,
  'guided_answers': ?guidedAnswers,
  'suggested_feelings': suggestedFeelings,
  'version': version,
  'analysis_pending': analysisPending,
};
