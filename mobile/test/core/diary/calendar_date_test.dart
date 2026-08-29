import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalendarDate', () {
    test('parse reads an ISO date', () {
      final date = CalendarDate.parse('2026-08-28');
      expect(date.year, 2026);
      expect(date.month, 8);
      expect(date.day, 28);
    });

    test('parse throws FormatException on nonsense', () {
      expect(() => CalendarDate.parse('not-a-date'), throwsFormatException);
      expect(() => CalendarDate.parse('2026-13-40'), throwsFormatException);
      expect(() => CalendarDate.parse('2026-02-30'), throwsFormatException);
      expect(() => CalendarDate.parse(''), throwsFormatException);
    });

    test('tryParse returns null instead of throwing', () {
      expect(CalendarDate.tryParse('nonsense'), isNull);
      expect(CalendarDate.tryParse(null), isNull);
      expect(
        CalendarDate.tryParse('2026-08-28'),
        const CalendarDate(2026, 8, 28),
      );
    });

    test('fromDateTime takes the date part', () {
      final date = CalendarDate.fromDateTime(DateTime(2026, 8, 28, 13, 5));
      expect(date, const CalendarDate(2026, 8, 28));
    });

    test('today reflects the injected clock', () {
      final date = CalendarDate.today(now: DateTime(2026, 8, 28, 23, 59));
      expect(date, const CalendarDate(2026, 8, 28));
    });

    test('toDateTime returns local midnight', () {
      final dt = const CalendarDate(2026, 8, 28).toDateTime();
      expect(dt, DateTime(2026, 8, 28));
      expect(dt.isUtc, isFalse);
    });

    test('toString is zero-padded ISO', () {
      expect(const CalendarDate(2026, 8, 28).toString(), '2026-08-28');
      expect(const CalendarDate(7, 1, 2).toString(), '0007-01-02');
    });

    test('weekday matches DateTime.weekday, 1 = Monday', () {
      // 2026-08-28 is a Friday.
      expect(const CalendarDate(2026, 8, 28).weekday, DateTime.friday);
      expect(const CalendarDate(2026, 8, 24).weekday, DateTime.monday);
    });

    test('addDays moves forward and backward, crossing month/year bounds', () {
      expect(
        const CalendarDate(2026, 8, 28).addDays(5),
        const CalendarDate(2026, 9, 2),
      );
      expect(
        const CalendarDate(2026, 1, 2).addDays(-5),
        const CalendarDate(2025, 12, 28),
      );
    });

    test('comparison operators order by date', () {
      const earlier = CalendarDate(2026, 8, 1);
      const later = CalendarDate(2026, 8, 2);
      expect(earlier < later, isTrue);
      expect(later > earlier, isTrue);
      expect(earlier.compareTo(later), lessThan(0));
      expect(later.compareTo(earlier), greaterThan(0));
      expect(earlier.compareTo(earlier), 0);
    });

    test('<= and >= include the equal case', () {
      const earlier = CalendarDate(2026, 8, 1);
      const later = CalendarDate(2026, 8, 2);
      expect(earlier <= later, isTrue);
      expect(earlier <= earlier, isTrue);
      expect(later <= earlier, isFalse);
      expect(later >= earlier, isTrue);
      expect(earlier >= earlier, isTrue);
      expect(earlier >= later, isFalse);
    });

    test('equality and hashCode are value-based', () {
      expect(const CalendarDate(2026, 8, 28), const CalendarDate(2026, 8, 28));
      expect(
        const CalendarDate(2026, 8, 28).hashCode,
        const CalendarDate(2026, 8, 28).hashCode,
      );
      expect(
        const CalendarDate(2026, 8, 28),
        isNot(const CalendarDate(2026, 8, 29)),
      );
    });

    test('sorts correctly with List.sort', () {
      final dates = [
        const CalendarDate(2026, 8, 28),
        const CalendarDate(2025, 1, 1),
        const CalendarDate(2026, 1, 1),
      ]..sort();
      expect(dates, [
        const CalendarDate(2025, 1, 1),
        const CalendarDate(2026, 1, 1),
        const CalendarDate(2026, 8, 28),
      ]);
    });
  });

  group('YearMonth', () {
    test('parse reads an ISO year-month', () {
      final ym = YearMonth.parse('2026-08');
      expect(ym.year, 2026);
      expect(ym.month, 8);
    });

    test('parse throws FormatException on nonsense', () {
      expect(() => YearMonth.parse('not-a-month'), throwsFormatException);
      expect(() => YearMonth.parse('2026-13'), throwsFormatException);
      expect(() => YearMonth.parse('2026-08-28'), throwsFormatException);
    });

    test('tryParse returns null instead of throwing', () {
      expect(YearMonth.tryParse('nonsense'), isNull);
      expect(YearMonth.tryParse(null), isNull);
      expect(YearMonth.tryParse('2026-08'), const YearMonth(2026, 8));
    });

    test('fromDate drops the day', () {
      expect(
        YearMonth.fromDate(const CalendarDate(2026, 8, 28)),
        const YearMonth(2026, 8),
      );
    });

    test('current reflects the injected clock', () {
      expect(
        YearMonth.current(now: DateTime(2026, 8, 28)),
        const YearMonth(2026, 8),
      );
    });

    test('toString is zero-padded ISO', () {
      expect(const YearMonth(2026, 8).toString(), '2026-08');
      expect(const YearMonth(7, 1).toString(), '0007-01');
    });

    test('addMonths moves forward and backward across year bounds', () {
      expect(const YearMonth(2026, 8).addMonths(5), const YearMonth(2027, 1));
      expect(const YearMonth(2026, 1).addMonths(-1), const YearMonth(2025, 12));
      expect(const YearMonth(2026, 8).addMonths(0), const YearMonth(2026, 8));
      expect(
        const YearMonth(2026, 8).addMonths(-20),
        const YearMonth(2024, 12),
      );
    });

    test('lengthInDays accounts for leap years', () {
      expect(const YearMonth(2026, 2).lengthInDays, 28);
      expect(const YearMonth(2024, 2).lengthInDays, 29);
      expect(const YearMonth(2026, 1).lengthInDays, 31);
      expect(const YearMonth(2026, 4).lengthInDays, 30);
    });

    test('firstDay and lastDay bound the month', () {
      const ym = YearMonth(2026, 2);
      expect(ym.firstDay, const CalendarDate(2026, 2, 1));
      expect(ym.lastDay, const CalendarDate(2026, 2, 28));
    });

    test('equality, hashCode and comparison are value-based', () {
      expect(const YearMonth(2026, 8), const YearMonth(2026, 8));
      expect(
        const YearMonth(2026, 8).hashCode,
        const YearMonth(2026, 8).hashCode,
      );
      expect(
        const YearMonth(2026, 1).compareTo(const YearMonth(2026, 8)),
        lessThan(0),
      );
    });
  });
}
