import 'reminder_schedule.dart';

/// [R-2] The weekly digest's wall-clock schedule: a day of the week plus a
/// time.
///
/// [weekday] uses [DateTime]'s own convention -- `1` (`DateTime.monday`)
/// through `7` (`DateTime.sunday`) -- rather than inventing a second one,
/// since [nextWeeklyOccurrence] compares it directly against
/// [DateTime.weekday].
///
/// Unlike [ReminderSlot] in `reminder_schedule.dart`, this carries no `id`:
/// there is exactly one digest schedule per device (a single toggle plus one
/// day/time, not a user-managed list), so `ReminderService` schedules it
/// under one fixed notification id of its own rather than deriving one per
/// instance.
final class const DigestSlot(
  final int weekday,
  final int hour,
  final int minute,
) {
  @override
  bool operator ==(Object other) =>
      other is DigestSlot &&
      other.weekday == weekday &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(weekday, hour, minute);

  @override
  String toString() =>
      '${_weekdayName(weekday)} '
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}

const List<String> _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _weekdayName(int weekday) =>
    weekday >= 1 && weekday <= 7 ? _weekdayNames[weekday - 1] : '?';

/// The next moment [slot] occurs at or after [now]: the same wall-clock rule
/// `reminder_schedule.dart#nextOccurrence` uses for a daily slot, extended to
/// a weekly one.
///
/// `now` exactly equal to the slot's clock time on its own weekday counts as
/// already passed -- see `nextOccurrence`'s own doc comment for why -- so the
/// search always lands on a moment strictly after `now`, at most seven days
/// out.
///
/// Calendar-date arithmetic throughout ([DateTime.add] on a date with no
/// time-of-day set), for the same daylight-saving reason `nextOccurrence`
/// documents: the slot's hour and minute are reapplied to each candidate day
/// afresh, never inherited from a fixed-length [Duration] added to a
/// timestamp.
///
/// The returned [DateTime] is UTC exactly when `now` is UTC, and local
/// otherwise, matching `nextOccurrence`.
DateTime nextWeeklyOccurrence(DigestSlot slot, {required DateTime now}) {
  DateTime atSlot(DateTime day) => now.isUtc
      ? DateTime.utc(day.year, day.month, day.day, slot.hour, slot.minute)
      : DateTime(day.year, day.month, day.day, slot.hour, slot.minute);

  final today = now.isUtc
      ? DateTime.utc(now.year, now.month, now.day)
      : DateTime(now.year, now.month, now.day);

  // `offset` runs to 7 inclusive, not 6: the slot's own weekday might be
  // today with its clock time already passed, and the next match is then
  // exactly one week out, not somewhere inside the six days in between.
  for (var offset = 0; offset <= 7; offset++) {
    final day = today.add(Duration(days: offset));
    if (day.weekday != slot.weekday) continue;
    final candidate = atSlot(day);
    if (candidate.isAfter(now)) return candidate;
  }
  // Unreachable: every weekday 1..7 appears at least once in an 8-day span,
  // and by the time `offset` reaches 7 the candidate is a full week after
  // `now`, which is always strictly later.
  throw StateError('nextWeeklyOccurrence found no match within 7 days');
}
