import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/features/calendar/year_grid.dart';
import 'package:find_my_patterns/features/today/entry_card.dart';
import 'package:find_my_patterns/features/today/writing_streak_line.dart';
import 'package:flutter/material.dart';

import '../../features/calendar/json_fixtures.dart';
import '../fake_http.dart';
import '../harness.dart';
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

/// Points across most months of the year, mixing positive and negative
/// scores and a couple of unconfirmed (`score: null`) days — a real diary's
/// year is not evenly one sentiment, and an empty year would never exercise
/// the painter's four cell states at all.
List<Map<String, Object?>> _yearGridPointsJson() => [
  for (var month = 1; month <= 12; month++)
    for (final day in [3, 17])
      seriesPointJson(
        date: CalendarDate(2026, month, day).toString(),
        score: switch (month % 3) {
          0 => null,
          1 => 1,
          _ => -1,
        },
        entryCount: month == 12 ? 12 : 2,
      ),
];

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
    ScreenCase(
      name: 'YearGrid',
      source: 'features/calendar/year_grid.dart',
      build: () => Harness(
        adapter: FakeHttpAdapter([
          FakeReply(200, body: seriesJson(points: _yearGridPointsJson())),
        ]),
      ).scope(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(body: SingleChildScrollView(child: YearGrid())),
        ),
      ),
    ),
    ScreenCase(
      name: 'WritingStreakLine',
      source: 'features/today/writing_streak_line.dart',
      build: () => MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(
          body: WritingStreakLine(streakDays: 12),
        ),
      ),
    ),
  ],
  unswept: const {},
);
