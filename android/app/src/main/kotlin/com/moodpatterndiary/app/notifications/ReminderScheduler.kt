package com.moodpatterndiary.app.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.time.Clock
import java.time.LocalDateTime
import java.time.LocalTime

/**
 * Schedules the four fixed daily reminder alarms (FR-013/FR-014, research.md §3). Uses exact,
 * Doze-surviving alarms (`setExactAndAllowWhileIdle`) since `WorkManager`'s periodic work can't
 * guarantee the within-one-minute timing SC-006 requires; falls back to an inexact
 * `setAndAllowWhileIdle` alarm if the user hasn't granted the exact-alarm permission on
 * Android 12+ rather than crashing.
 *
 * Each of the 4 daily times is scheduled as its own one-shot alarm; [ReminderReceiver] re-arms
 * the same slot for the next day every time it fires (AlarmManager has no built-in "daily at a
 * fixed clock time" repeat that survives Doze reliably).
 */
class ReminderScheduler(
    private val context: Context,
    private val clock: Clock = Clock.systemDefaultZone(),
) {
    private val alarmManager: AlarmManager
        get() = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    fun scheduleAll() {
        REMINDER_TIMES.forEach { time -> scheduleNext(time) }
    }

    fun cancelAll() {
        REMINDER_TIMES.forEach { time -> alarmManager.cancel(pendingIntentFor(time)) }
    }

    fun scheduleNext(time: LocalTime) {
        val triggerAtMillis = nextTriggerMillis(time, clock)
        val pendingIntent = pendingIntentFor(time)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            } else {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            }
        } catch (_: SecurityException) {
            // Exact-alarm permission was revoked between the check and the call (or on an OEM
            // that requires it even below API 31) -- degrade gracefully instead of crashing.
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        }
    }

    private fun pendingIntentFor(time: LocalTime): PendingIntent {
        val intent =
            Intent(context, ReminderReceiver::class.java).apply {
                action = ReminderReceiver.ACTION_REMINDER_FIRED
                putExtra(ReminderReceiver.EXTRA_REMINDER_MINUTE_OF_DAY, time.toSecondOfDay() / 60)
            }
        val requestCode = time.hour * 100 + time.minute
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        /** The four fixed daily reminder times required by FR-013. */
        val REMINDER_TIMES: List<LocalTime> =
            listOf(
                LocalTime.of(9, 0),
                LocalTime.of(12, 0),
                LocalTime.of(18, 0),
                LocalTime.of(21, 0),
            )

        /**
         * Pure, deterministic next-fire-time computation (unit-tested in
         * ReminderSchedulerTest, no Android instrumentation needed): the next occurrence of
         * [time] on the clock's zone -- today if it hasn't happened yet, otherwise tomorrow.
         * "Now equals exactly [time]" counts as already passed, so an alarm always fires at
         * least one full day out rather than immediately re-firing.
         */
        fun nextTriggerMillis(
            time: LocalTime,
            clock: Clock = Clock.systemDefaultZone(),
        ): Long {
            val zone = clock.zone
            val now = LocalDateTime.now(clock)
            var candidateDate = now.toLocalDate()
            var candidate = LocalDateTime.of(candidateDate, time)
            if (!candidate.isAfter(now)) {
                candidateDate = candidateDate.plusDays(1)
                candidate = LocalDateTime.of(candidateDate, time)
            }
            return candidate.atZone(zone).toInstant().toEpochMilli()
        }
    }
}
