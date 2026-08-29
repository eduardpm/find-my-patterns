/// Wire fixtures shared by the Today feature's tests.
library;

import 'package:find_my_patterns/core/diary/calendar_date.dart';

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

/// One entry, as `GET /entries?date=...` returns it.
Map<String, Object?> entryJson({
  String id = 'entry-1',
  CalendarDate? entryDate,
  String feelingKey = 'happy',
  int version = 1,
  String rawText = 'a day',
  String createdAt = '2026-08-28T09:00:00',
  bool analysisPending = false,
}) => {
  'id': id,
  'created_at': createdAt,
  'entry_date': (entryDate ?? CalendarDate(2026, 8, 28)).toString(),
  'mode': 'freeform',
  'raw_text': rawText,
  'feeling_key': feelingKey,
  'feeling_keys': [feelingKey],
  'feeling_source': 'confirmed',
  'version': version,
  'analysis_pending': analysisPending,
};

/// A `GET /entries?date=...` body wrapping [entries].
Map<String, Object?> entriesJson(List<Map<String, Object?>> entries) => {
  'entries': entries,
};

/// One day's roll-up, as nested under a `GET /monthly-summary` response.
Map<String, Object?> daySummaryJson({
  required CalendarDate date,
  List<String> feelings = const ['happy'],
  int? intensity,
  int? entryCount,
}) => {
  'date': date.toString(),
  'feelings': feelings,
  'intensity': intensity,
  'entry_count': entryCount ?? feelings.length,
};

/// A `GET /monthly-summary` body wrapping [days].
Map<String, Object?> monthlySummaryJson({
  required List<Map<String, Object?>> days,
  String month = '2026-08',
}) => {
  'month': month,
  'days': days,
  'totals_by_feeling': <String, Object?>{},
  'average_entries_per_day': 0.0,
};

/// A `GET /insights/series` body naming [days] as the days with at least
/// one entry -- the presence signal `computeWritingStreak` (#40) reads.
/// Every named day gets one entry; `score` and `confirmed_feeling_count`
/// are filled with harmless values since nothing in this app's tests reads
/// them yet.
Map<String, Object?> seriesJson({List<CalendarDate> days = const []}) => {
  'granularity': 'day',
  'points': [
    for (final date in days)
      {
        'date': date.toString(),
        'score': null,
        'entry_count': 1,
        'confirmed_feeling_count': 0,
      },
  ],
  'constants': {'recency_window_days': 14},
};
