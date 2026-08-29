import 'package:find_my_patterns/core/notifications/digest_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextWeeklyOccurrence', () {
    test(
      'returns today\'s trigger time when today is the slot\'s weekday and '
      'the time has not passed yet',
      () {
        // 2026-07-27 is a Monday.
        final now = DateTime.utc(2026, 7, 27, 8);
        final result = nextWeeklyOccurrence(
          const DigestSlot(DateTime.monday, 9, 0),
          now: now,
        );
        expect(result, DateTime.utc(2026, 7, 27, 9));
      },
    );

    test(
      'rolls over to next week when today is the slot\'s weekday but the '
      'time already passed',
      () {
        final now = DateTime.utc(2026, 7, 27, 13); // Monday 13:00
        final result = nextWeeklyOccurrence(
          const DigestSlot(DateTime.monday, 9, 0),
          now: now,
        );
        expect(result, DateTime.utc(2026, 8, 3, 9)); // the following Monday
      },
    );

    test(
      'rolls over to next week when now is exactly the slot\'s time',
      () {
        final now = DateTime.utc(2026, 7, 27, 9); // Monday 09:00 exactly
        final result = nextWeeklyOccurrence(
          const DigestSlot(DateTime.monday, 9, 0),
          now: now,
        );
        expect(result, DateTime.utc(2026, 8, 3, 9));
      },
    );

    test(
      'finds the next occurrence of a different weekday later in the week',
      () {
        final now = DateTime.utc(2026, 7, 27, 8); // Monday
        final result = nextWeeklyOccurrence(
          const DigestSlot(DateTime.sunday, 18, 0),
          now: now,
        );
        expect(result, DateTime.utc(2026, 8, 2, 18)); // the coming Sunday
      },
    );

    test(
      'issue #42\'s own default: Sunday 18:00, computed from a midweek now',
      () {
        final now = DateTime.utc(2026, 7, 29, 12); // Wednesday
        final result = nextWeeklyOccurrence(
          const DigestSlot(DateTime.sunday, 18, 0),
          now: now,
        );
        expect(result, DateTime.utc(2026, 8, 2, 18));
      },
    );

    test('handles a month rollover', () {
      final now = DateTime.utc(2026, 7, 31, 22); // Friday
      final result = nextWeeklyOccurrence(
        const DigestSlot(DateTime.friday, 9, 0),
        now: now,
      );
      expect(result, DateTime.utc(2026, 8, 7, 9));
    });

    test('handles a year rollover', () {
      final now = DateTime.utc(2026, 12, 31, 22); // Thursday
      final result = nextWeeklyOccurrence(
        const DigestSlot(DateTime.thursday, 9, 0),
        now: now,
      );
      expect(result, DateTime.utc(2027, 1, 7, 9));
    });

    test(
      'preserves whether now was UTC or local, rather than normalising to '
      'one or the other',
      () {
        final utcResult = nextWeeklyOccurrence(
          const DigestSlot(DateTime.monday, 9, 0),
          now: DateTime.utc(2026, 7, 27, 8),
        );
        expect(utcResult.isUtc, isTrue);

        final localResult = nextWeeklyOccurrence(
          const DigestSlot(DateTime.monday, 9, 0),
          now: DateTime(2026, 7, 27, 8),
        );
        expect(localResult.isUtc, isFalse);
      },
    );

    test(
      'a day added to roll over is calendar-date arithmetic, not a 24-hour '
      'duration, so it lands on the same wall-clock slot regardless of any '
      'DST shift the host applies between now and the target day',
      () {
        // 2026-03-28 is a Saturday; the next Sunday is the following day.
        final now = DateTime(2026, 3, 28, 23);
        final result = nextWeeklyOccurrence(
          const DigestSlot(DateTime.sunday, 9, 0),
          now: now,
        );
        expect(result.year, 2026);
        expect(result.month, 3);
        expect(result.day, 29);
        expect(result.hour, 9);
        expect(result.minute, 0);
      },
    );
  });

  group('DigestSlot as a value', () {
    test('two slots with the same weekday and time are the same slot', () {
      expect(
        const DigestSlot(DateTime.sunday, 18, 0),
        const DigestSlot(DateTime.sunday, 18, 0),
      );
      expect(
        const DigestSlot(DateTime.sunday, 18, 0).hashCode,
        const DigestSlot(DateTime.sunday, 18, 0).hashCode,
      );
    });

    test('slots differing in weekday, hour or minute all differ', () {
      const base = DigestSlot(DateTime.sunday, 18, 0);
      expect(base, isNot(const DigestSlot(DateTime.monday, 18, 0)));
      expect(base, isNot(const DigestSlot(DateTime.sunday, 19, 0)));
      expect(base, isNot(const DigestSlot(DateTime.sunday, 18, 30)));
    });

    test('reads as a weekday name and a zero-padded wall-clock time', () {
      expect(
        const DigestSlot(DateTime.sunday, 18, 0).toString(),
        'Sunday 18:00',
      );
      expect(
        const DigestSlot(DateTime.wednesday, 9, 5).toString(),
        'Wednesday 09:05',
      );
    });
  });
}
