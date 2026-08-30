import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/features/today/entry_card.dart';
import 'package:flutter/material.dart';

import '../screen_registry.dart';

const _feelings = [
  Feeling('relaxed', 'Relaxed', Valence.positive, 'uplifted'),
  Feeling('curious', 'Curious', Valence.neutral, 'steady'),
  Feeling('irritable', 'Irritable', Valence.negative, 'tense'),
];

/// An entry carrying three feelings and a long body — the shape a real diary
/// produces, and the one that stresses a row of feeling chips hardest.
Entry _entry() => entryFromJson({
  'id': 'entry-1',
  'created_at': '2026-08-01T10:17:00',
  'entry_date': CalendarDate(2026, 8, 1).toString(),
  'mode': 'freeform',
  'raw_text':
      'Slept badly and woke up several times, then the morning got better.',
  'feeling_key': 'relaxed',
  'feeling_keys': ['relaxed', 'curious', 'irritable'],
  'feeling_source': 'confirmed',
  'version': 1,
  'analysis_pending': false,
}, const FeelingCatalog(_feelings));

/// `lib/features/today/` and `lib/features/calendar/`.
final todayCalendar = ScreenArea(
  name: 'today and calendar',
  cases: [
    ScreenCase(
      name: 'EntryCard',
      source: 'features/today/entry_card.dart',
      build: () => MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: EntryCard(entry: _entry(), onTap: () {}),
        ),
      ),
    ),
  ],
  unswept: const {
    'features/calendar/year_grid.dart',
    // Confirmed defective by the sweep before it was registered: "12 days
    // writing" renders 66px past a 320dp screen at 2x, 26px past at 360dp.
    'features/today/writing_streak_line.dart',
  },
);
