// Wire-shaped JSON fixtures for the endpoints behind the calendar feature:
// `GET /feelings`, `GET /monthly-summary`, `GET /entries`, `GET
// /entries/{id}`, `PATCH /entries/{id}`. Field names are snake_case,
// matching what `lib/core/diary` decodes.

/// The feeling catalog every one of these endpoints resolves feeling keys
/// through before it can decode anything else.
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
  ],
};

/// One day in `GET /monthly-summary`'s `days` array.
Map<String, Object?> daySummaryJson({
  required String date,
  List<String> feelings = const [],
  int? intensity,
}) => {'date': date, 'feelings': feelings, 'intensity': intensity};

/// `GET /monthly-summary`'s whole response.
Map<String, Object?> monthlySummaryJson({
  required String month,
  List<Map<String, Object?>> days = const [],
  Map<String, int> totalsByFeeling = const {},
  double averageEntriesPerDay = 0,
}) => {
  'month': month,
  'days': days,
  'totals_by_feeling': totalsByFeeling,
  'average_entries_per_day': averageEntriesPerDay,
};

/// One entry, as `GET /entries`, `GET /entries/{id}` and `PATCH
/// /entries/{id}` all shape it.
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
