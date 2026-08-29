import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/mood_series.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('moodSeriesPointFromJson', () {
    test('decodes a scored day', () {
      final point = moodSeriesPointFromJson({
        'date': '2026-08-25',
        'score': 0.62,
        'entry_count': 3,
        'confirmed_feeling_count': 4,
      });

      expect(point.date, const CalendarDate(2026, 8, 25));
      expect(point.score, 0.62);
      expect(point.entryCount, 3);
      expect(point.confirmedFeelingCount, 4);
    });

    // I5-07's rule: a day logged with entries but no *confirmed* feeling
    // carries a real entry count and a null score, not a zero -- see the
    // day-score contract in the backend's `constants.ts`.
    test('a null score is a gap, not a zero, and keeps its entry count', () {
      final point = moodSeriesPointFromJson({
        'date': '2026-08-25',
        'score': null,
        'entry_count': 1,
        'confirmed_feeling_count': 0,
      });

      expect(point.score, isNull);
      expect(point.entryCount, 1);
    });

    test('entry_count and confirmed_feeling_count default to zero', () {
      final point = moodSeriesPointFromJson({
        'date': '2026-08-25',
        'score': null,
      });

      expect(point.entryCount, 0);
      expect(point.confirmedFeelingCount, 0);
    });
  });

  group('moodSeriesFromJson', () {
    test('decodes every point, in the order the backend sent them', () {
      final series = moodSeriesFromJson({
        'granularity': 'day',
        'points': [
          {'date': '2026-08-24', 'score': -0.2, 'entry_count': 2},
          {'date': '2026-08-25', 'score': 0.5, 'entry_count': 1},
        ],
        'constants': <String, Object?>{},
      });

      expect(series.points, hasLength(2));
      expect(series.points[0].date, const CalendarDate(2026, 8, 24));
      expect(series.points[1].date, const CalendarDate(2026, 8, 25));
    });

    // Days with no entries are omitted from the wire response entirely
    // (see `InsightsApi.series`'s doc) rather than sent as zero-count
    // points, so an absent `points` array decodes the same way a genuinely
    // empty range does: no points at all.
    test('an absent points array decodes to an empty series', () {
      final series = moodSeriesFromJson(const {'granularity': 'day'});
      expect(series.points, isEmpty);
    });
  });
}
