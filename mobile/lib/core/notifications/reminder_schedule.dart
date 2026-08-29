/// A daily check-in reminder's wall-clock time.
///
/// Originally ported from `ReminderScheduler.REMINDER_TIMES` (Kotlin), which
/// fixed every device to the same four slots. Reminders are now user
/// configured — see `ReminderTime` in `core/settings/settings.dart`, which
/// pairs an hour and minute like this one with whether the user has turned
/// it on — so this type stays the bare, schedulable value the two share.
final class const ReminderSlot(final int hour, final int minute) {
  /// A stable id for this slot, used as both the scheduled-notification id
  /// and the payload that identifies which slot a tap came from.
  ///
  /// Derived from minute-of-day — `hour * 60 + minute` — exactly as the
  /// Kotlin's `ReminderNotifier.showReminder` id does, so the id a release
  /// used yesterday is still the id it uses today: a device that already has
  /// this slot scheduled or showing must keep recognising it across an app
  /// update, not get a duplicate under a newly invented id.
  int get id => hour * 60 + minute;

  @override
  bool operator ==(Object other) =>
      other is ReminderSlot && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}

/// The next moment [slot] occurs at or after [now]: later today if the slot's
/// clock time has not happened yet, otherwise tomorrow.
///
/// Pure and deterministic — ported from
/// `ReminderScheduler.nextTriggerMillis` (Kotlin), the one piece of this
/// subsystem worth testing without a platform, because it is the one piece
/// with real logic in it.
///
/// `now` exactly equal to the slot's clock time counts as already passed, so
/// a reminder always lands a full day out rather than firing again the
/// instant it was just shown — the same call the Kotlin makes, so an app
/// that is re-armed at the moment its own alarm fires doesn't immediately
/// re-fire.
///
/// The day rolled over to reach "tomorrow" is calendar-date arithmetic —
/// [DateTime.add] on a date with no time-of-day set, mirroring the Kotlin's
/// `LocalDate.plusDays(1)` — never a 24-hour [Duration] added to a
/// timestamp. That distinction is what keeps the result correct across a
/// daylight-saving transition between `now` and the target day: the
/// slot's hour and minute are always reapplied to the rolled-over date
/// afresh, rather than inherited from adding a fixed number of hours.
///
/// The returned [DateTime] is UTC exactly when `now` is UTC, and local
/// otherwise — this function never converts between the two. Tests drive it
/// with a fixed UTC `now` for a host-independent result; `ReminderService`
/// calls it with the device's real local `DateTime.now()`, leaving Dart's
/// own timezone database to resolve that local wall-clock time to an absolute
/// instant only once, downstream.
DateTime nextOccurrence(ReminderSlot slot, {required DateTime now}) {
  DateTime atSlot(DateTime day) => now.isUtc
      ? DateTime.utc(day.year, day.month, day.day, slot.hour, slot.minute)
      : DateTime(day.year, day.month, day.day, slot.hour, slot.minute);

  final candidate = atSlot(now);
  if (candidate.isAfter(now)) return candidate;

  final today = now.isUtc
      ? DateTime.utc(now.year, now.month, now.day)
      : DateTime(now.year, now.month, now.day);
  return atSlot(today.add(const Duration(days: 1)));
}
