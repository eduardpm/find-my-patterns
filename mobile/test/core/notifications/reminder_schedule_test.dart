import 'package:find_my_patterns/core/notifications/reminder_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kReminderTimes', () {
    test('contains exactly the four spec-required daily times, in order', () {
      expect(kReminderTimes, [
        const ReminderSlot(9, 0),
        const ReminderSlot(12, 0),
        const ReminderSlot(18, 0),
        const ReminderSlot(21, 0),
      ]);
    });

    test('ids are minute-of-day, so they stay stable across releases', () {
      expect(kReminderTimes.map((slot) => slot.id), [540, 720, 1080, 1260]);
    });
  });

  group('nextOccurrence', () {
    test(
      'returns today\'s trigger time when the target has not passed yet',
      () {
        final now = DateTime.utc(2026, 7, 27, 8);
        final result = nextOccurrence(const ReminderSlot(9, 0), now: now);
        expect(result, DateTime.utc(2026, 7, 27, 9));
      },
    );

    test('rolls over to tomorrow when the target already passed today', () {
      final now = DateTime.utc(2026, 7, 27, 13);
      final result = nextOccurrence(const ReminderSlot(9, 0), now: now);
      expect(result, DateTime.utc(2026, 7, 28, 9));
    });

    test(
      'rolls over to tomorrow when now is exactly the target time',
      () {
        final now = DateTime.utc(2026, 7, 27, 9);
        final result = nextOccurrence(const ReminderSlot(9, 0), now: now);
        expect(result, DateTime.utc(2026, 7, 28, 9));
      },
    );

    test('computes an independent next occurrence for each daily slot', () {
      final now = DateTime.utc(2026, 7, 27, 10, 30);
      final today = DateTime.utc(2026, 7, 27);
      final tomorrow = DateTime.utc(2026, 7, 28);

      expect(
        nextOccurrence(const ReminderSlot(9, 0), now: now),
        DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day, 9),
      );
      expect(
        nextOccurrence(const ReminderSlot(12, 0), now: now),
        DateTime.utc(today.year, today.month, today.day, 12),
      );
      expect(
        nextOccurrence(const ReminderSlot(18, 0), now: now),
        DateTime.utc(today.year, today.month, today.day, 18),
      );
      expect(
        nextOccurrence(const ReminderSlot(21, 0), now: now),
        DateTime.utc(today.year, today.month, today.day, 21),
      );
    });

    test('handles a month rollover', () {
      final now = DateTime.utc(2026, 7, 31, 22);
      final result = nextOccurrence(const ReminderSlot(9, 0), now: now);
      expect(result, DateTime.utc(2026, 8, 1, 9));
    });

    test('handles a year rollover', () {
      final now = DateTime.utc(2026, 12, 31, 22);
      final result = nextOccurrence(const ReminderSlot(9, 0), now: now);
      expect(result, DateTime.utc(2027, 1, 1, 9));
    });

    test(
      'preserves whether now was UTC or local, rather than normalising to '
      'one or the other',
      () {
        final utcResult = nextOccurrence(
          const ReminderSlot(9, 0),
          now: DateTime.utc(2026, 7, 27, 8),
        );
        expect(utcResult.isUtc, isTrue);

        final localResult = nextOccurrence(
          const ReminderSlot(9, 0),
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
        // A local (non-UTC) now lets the host's real timezone rules apply;
        // the result must still show the requested wall-clock slot on the
        // following calendar day, never shifted by an hour.
        final now = DateTime(2026, 3, 28, 23);
        final result = nextOccurrence(const ReminderSlot(9, 0), now: now);
        expect(result.year, 2026);
        expect(result.month, 3);
        expect(result.day, 29);
        expect(result.hour, 9);
        expect(result.minute, 0);
      },
    );
  });
  _slotValueSemantics();
}

void _slotValueSemantics() {
  group('ReminderSlot as a value', () {
    test('two slots at the same time are the same slot', () {
      expect(const ReminderSlot(9, 0), const ReminderSlot(9, 0));
      expect(
        const ReminderSlot(9, 0).hashCode,
        const ReminderSlot(9, 0).hashCode,
      );
    });

    test('slots at different times differ', () {
      expect(const ReminderSlot(9, 0), isNot(const ReminderSlot(9, 30)));
      expect(const ReminderSlot(9, 0), isNot(const ReminderSlot(21, 0)));
    });

    test('reads as a zero-padded wall-clock time', () {
      expect(const ReminderSlot(9, 0).toString(), '09:00');
      expect(const ReminderSlot(21, 5).toString(), '21:05');
    });
  });
}
