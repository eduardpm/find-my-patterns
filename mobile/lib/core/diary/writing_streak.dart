import 'calendar_date.dart';

/// How many days back the Today screen asks `GET /insights/series` to
/// cover when computing the writing streak (#40).
///
/// 400 rather than some smaller, more "typical" window: it is the backend's
/// own `MAX_SERIES_RANGE_DAYS` cap for `granularity=day` (see
/// `insights.controller.ts`'s day-score doc), so this is the longest streak
/// one call can ever confirm in full. A streak longer than that is
/// undercounted rather than mis-stated -- the number shown is still every
/// day this call could see, just not proof of every day the diary holds.
const int writingStreakQueryWindowDays = 400;

/// Computes the current writing streak: the count of consecutive calendar
/// days, ending on [today] or the day before it, each with at least one
/// entry in [entryDates].
///
/// [entryDates] holds every day known to have at least one entry --
/// `entry_date` as the backend assigned it, never a date derived from
/// `created_at`, so the day boundary this counts by is the same one the
/// rest of the app already draws entries into (Task 4).
///
/// The rule from #40's Task 1: a streak is not broken until the day that
/// would break it is over. If [today] has no entry yet, this looks at
/// [today] minus one day instead -- the day is still in progress, so a
/// streak that reached yesterday still counts as unbroken, and does not
/// drop to zero the moment the clock rolls past midnight only to jump back
/// the instant something is written. Once a full day has passed with
/// nothing recorded, the gap is real: walking backward from [today] (or
/// yesterday) stops at the first missing day, so an older run of entries on
/// the far side of a gap is never folded into today's count.
int computeWritingStreak({
  required Set<CalendarDate> entryDates,
  required CalendarDate today,
}) {
  var cursor = entryDates.contains(today) ? today : today.addDays(-1);
  var streak = 0;
  while (entryDates.contains(cursor)) {
    streak++;
    cursor = cursor.addDays(-1);
  }
  return streak;
}
