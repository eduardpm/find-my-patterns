import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/monthly_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const happy = Feeling('happy', 'Happy', Valence.positive, 'uplifted');
  const sad = Feeling('sad', 'Sad', Valence.negative, 'low');
  final catalog = FeelingCatalog([happy, sad]);

  group('DaySummary', () {
    test('holds an optional intensity', () {
      const withIntensity = DaySummary(
        CalendarDate(2026, 8, 1),
        [],
        intensity: 4,
      );
      const withoutIntensity = DaySummary(CalendarDate(2026, 8, 1), []);
      expect(withIntensity.intensity, 4);
      expect(withoutIntensity.intensity, isNull);
    });
  });

  group('daySummaryFromJson', () {
    test('decodes the date, feelings, and intensity', () {
      final day = daySummaryFromJson({
        'date': '2026-08-01',
        'feelings': ['happy', 'sad'],
        'intensity': 3,
      }, catalog);
      expect(day.date, const CalendarDate(2026, 8, 1));
      expect(day.feelings, [happy, sad]);
      expect(day.intensity, 3);
    });

    test('feelings defaults to empty and drops unknown keys', () {
      final day = daySummaryFromJson({
        'date': '2026-08-01',
        'feelings': ['happy', 'invented'],
      }, catalog);
      expect(day.feelings, [happy]);
    });

    test('an absent intensity means never rated', () {
      final day = daySummaryFromJson({'date': '2026-08-01'}, catalog);
      expect(day.intensity, isNull);
    });
  });

  group('monthlySummaryFromJson', () {
    test('decodes every field', () {
      final summary = monthlySummaryFromJson({
        'month': '2026-08',
        'days': [
          {
            'date': '2026-08-01',
            'feelings': ['happy'],
          },
        ],
        'totals_by_feeling': {'happy': 5, 'sad': 2},
        'average_entries_per_day': 1.5,
      }, catalog);
      expect(summary.month, const YearMonth(2026, 8));
      expect(summary.days, hasLength(1));
      expect(summary.averageEntriesPerDay, 1.5);
    });

    test(
      'totalsByFeeling is built by walking the catalog, in its order',
      () {
        final summary = monthlySummaryFromJson({
          'month': '2026-08',
          'totals_by_feeling': {'sad': 2, 'happy': 5},
        }, catalog);
        expect(summary.totalsByFeeling.keys.toList(), [happy, sad]);
        expect(summary.totalsByFeeling[happy], 5);
        expect(summary.totalsByFeeling[sad], 2);
      },
    );

    test('a feeling with no entry in the response is omitted, not zero', () {
      final summary = monthlySummaryFromJson({
        'month': '2026-08',
        'totals_by_feeling': {'happy': 5},
      }, catalog);
      expect(summary.totalsByFeeling.containsKey(sad), isFalse);
    });

    test('average_entries_per_day defaults to 0.0', () {
      final summary = monthlySummaryFromJson({'month': '2026-08'}, catalog);
      expect(summary.averageEntriesPerDay, 0.0);
    });

    test('days defaults to empty', () {
      final summary = monthlySummaryFromJson({'month': '2026-08'}, catalog);
      expect(summary.days, isEmpty);
    });

    test('an unparseable month falls back to the current month', () {
      final now = DateTime(2026, 8, 15);
      final summary = monthlySummaryFromJson(
        {'month': 'nonsense'},
        catalog,
        now: now,
      );
      expect(summary.month, const YearMonth(2026, 8));
    });
  });
}
