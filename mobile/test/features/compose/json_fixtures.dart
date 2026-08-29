/// Wire fixtures shared by the compose feature's tests.
library;

/// A `GET /feelings` body with `happy` and `sad`, each in their own group.
Map<String, Object?> feelingsCatalogJson() => {
  'feelings': [
    {
      'key': 'happy',
      'label': 'Happy',
      'valence': 'positive',
      'group_key': 'uplifted',
    },
    {'key': 'sad', 'label': 'Sad', 'valence': 'negative', 'group_key': 'low'},
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
  ],
};

/// A `GET /guiding-questions` body: one mandatory prompt, one optional
/// prompt triggered by the word "work".
Map<String, Object?> guidingQuestionsJson() => {
  'questions': [
    {
      'key': 'general',
      'category': 'general',
      'prompt_text': "What's on your mind?",
      'trigger_keywords': <String>[],
      'is_mandatory': true,
    },
    {
      'key': 'work',
      'category': 'small_influences',
      'prompt_text': 'How was work?',
      'trigger_keywords': ['work'],
      'is_mandatory': false,
    },
  ],
};

/// A `GET /insights` body carrying just the engine constants, or the
/// [patterns] a test wants alongside them -- e.g. for the first-pattern
/// celebration (L-3/#38), which reads this same endpoint's `patterns` list
/// fresh on every confirm.
Map<String, Object?> insightsJson({
  int minIntensity = 1,
  int maxIntensity = 5,
  List<Map<String, Object?>> patterns = const [],
}) => {
  'patterns': patterns,
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
    'min_intensity': minIntensity,
    'max_intensity': maxIntensity,
  },
};

/// One entry, as `POST /entries` or `PATCH /entries/{id}` returns it.
Map<String, Object?> entryJson({
  String id = 'entry-1',
  String feelingKey = 'happy',
  List<String>? feelingKeys,
  int version = 1,
  String rawText = 'a day',
  List<Map<String, Object?>>? suggestedFeelings,
  bool analysisPending = false,
}) => {
  'id': id,
  'created_at': '2026-07-28T13:05:00',
  'entry_date': '2026-07-28',
  'mode': 'freeform',
  'raw_text': rawText,
  'feeling_key': feelingKey,
  'feeling_keys': feelingKeys ?? [feelingKey],
  'feeling_source': 'suggested',
  'version': version,
  'analysis_pending': analysisPending,
  'suggested_feelings': ?suggestedFeelings,
};

/// An entry as `POST /entries` returns it the moment analysis is queued and
/// nobody -- neither the analyser nor the user -- has chosen a feeling yet:
/// `feeling_key`/`feeling_keys` are genuinely empty and `feeling_source` is
/// `'unset'`, unlike [entryJson]'s default (which always carries
/// `feeling_key: 'happy'`, `feeling_source: 'suggested'`, useful for tests
/// where an immediate suggestion is exactly the point, but wrong for a poll
/// sequence's *pending* replies -- a `feeling_key` already present there
/// would seed a composer's selection before the real suggestion arrives).
Map<String, Object?> unanalysedEntryJson({
  String id = 'entry-1',
  int version = 1,
  String rawText = 'a day',
}) => {
  'id': id,
  'created_at': '2026-07-28T13:05:00',
  'entry_date': '2026-07-28',
  'mode': 'freeform',
  'raw_text': rawText,
  'feeling_key': null,
  'feeling_keys': <String>[],
  'feeling_source': 'unset',
  'version': version,
  'analysis_pending': true,
  'suggested_feelings': <Map<String, Object?>>[],
};

/// One suggested-feeling DTO, nested under an entry's `suggested_feelings`.
Map<String, Object?> suggestedFeelingJson({
  String key = 'happy',
  double confidence = 0.9,
}) => {'key': key, 'confidence': confidence};

/// One pattern DTO, nested under a `GET /insights` body's `patterns` list --
/// only the fields `patternFromJson` requires plus [occurrenceCount],
/// which the first-pattern celebration's notification/card copy is derived
/// from (L-3/#38).
Map<String, Object?> patternJson({
  String id = 'pattern-1',
  String topic = 'work',
  int occurrenceCount = 3,
}) => {
  'id': id,
  'kind': 'forward',
  'topic': topic,
  'occurrence_count': occurrenceCount,
  'narrative_text': 'You often feel happy about $topic.',
  'suggestion_text': 'Keep it up.',
  'last_updated_at': '2026-07-28T13:05:00Z',
};

/// A `GET /entries/{id}/echo` body carrying [count] narrative sentences.
Map<String, Object?> echoJson({int count = 1}) => {
  'echoes': [
    for (var i = 0; i < count; i++)
      {
        'pattern_id': 'pattern-$i',
        'topic': 'topic-$i',
        'feeling': 'happy',
        'occurrence_count': 4,
        'present_count': 3,
        'present_total': 4,
        'lift': 2.0,
        'narrative_text': 'You often feel happy about topic-$i.',
      },
  ],
};
