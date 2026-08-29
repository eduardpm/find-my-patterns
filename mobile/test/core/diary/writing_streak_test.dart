// #40's acceptance criteria, verified directly against the pure function
// rather than through the controller or the widget: every case the issue
// lists by name gets its own test here.

import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/writing_streak.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const today = CalendarDate(2026, 8, 28);
  final yesterday = today.addDays(-1);

  /// [today] and the [count] - 1 days before it, consecutive.
  Set<CalendarDate> consecutiveDaysEndingToday(int count) => {
    for (var i = 0; i < count; i++) today.addDays(-i),
  };

  group('computeWritingStreak', () {
    test('gap yesterday: today and yesterday both empty resets to zero', () {
      // A run further back exists, but a full empty day -- today and
      // yesterday both unwritten -- breaks it; nothing on the far side of
      // the gap is folded into the count.
      final entryDates = {
        today.addDays(-3),
        today.addDays(-4),
        today.addDays(-5),
      };

      expect(
        computeWritingStreak(entryDates: entryDates, today: today),
        0,
      );
    });

    test('entry today only is a streak of one', () {
      final entryDates = {today};

      expect(computeWritingStreak(entryDates: entryDates, today: today), 1);
    });

    test('3 consecutive days ending today shows 3', () {
      final entryDates = consecutiveDaysEndingToday(3);

      expect(computeWritingStreak(entryDates: entryDates, today: today), 3);
    });

    test(
      'today empty but yesterday streaking still counts -- not broken '
      'until the day is over',
      () {
        // Nothing recorded for `today` yet, but the streak reaching
        // yesterday is unbroken: today is still in progress, so this reads
        // as of yesterday instead of dropping to zero at midnight.
        final entryDates = {
          yesterday,
          yesterday.addDays(-1),
          yesterday.addDays(-2),
        };

        expect(computeWritingStreak(entryDates: entryDates, today: today), 3);
      },
    );

    test('no entries at all is zero', () {
      expect(computeWritingStreak(entryDates: const {}, today: today), 0);
    });

    test('an older run beyond a gap does not extend today\'s streak', () {
      // Written today and yesterday, then a gap, then an older run. The
      // older run is real diary history, but it is not part of the streak
      // that is still unbroken right now.
      final entryDates = {
        today,
        yesterday,
        today.addDays(-5),
        today.addDays(-6),
        today.addDays(-7),
      };

      expect(computeWritingStreak(entryDates: entryDates, today: today), 2);
    });

    test('a gap the day before yesterday still lets yesterday and today '
        'count', () {
      final entryDates = {today, yesterday};

      expect(computeWritingStreak(entryDates: entryDates, today: today), 2);
    });
  });

  group('writingStreakQueryWindowDays', () {
    test('matches the backend\'s day-granularity range cap', () {
      // `GET /insights/series` answers 422 above this many days at
      // `granularity=day` (`MAX_SERIES_RANGE_DAYS` in
      // `backend/src/insights/constants.ts`) -- this is the widest window
      // the Today screen can ever ask for in one call, so any real streak
      // longer than this is undercounted rather than over-queried.
      expect(writingStreakQueryWindowDays, 400);
    });
  });
}
