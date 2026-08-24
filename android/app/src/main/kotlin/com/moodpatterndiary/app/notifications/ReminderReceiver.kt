package com.moodpatterndiary.app.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.time.LocalTime

/**
 * Handles both alarm fires and boot-completed re-arming (FR-013, US4).
 *
 * AlarmManager alarms do not survive a device reboot, so [Intent.ACTION_BOOT_COMPLETED]
 * re-schedules all four daily reminders from scratch. When one of those alarms actually fires,
 * this posts the notification and immediately re-arms that same time slot for tomorrow (see
 * [ReminderScheduler] for why each slot is a one-shot alarm rather than a repeating one).
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                ReminderScheduler(context).scheduleAll()
            }
            ACTION_REMINDER_FIRED -> {
                val minuteOfDay = intent.getIntExtra(EXTRA_REMINDER_MINUTE_OF_DAY, -1)
                if (minuteOfDay < 0) return

                ReminderNotifier(context).showReminder(minuteOfDay)

                val time = LocalTime.ofSecondOfDay(minuteOfDay * 60L)
                ReminderScheduler(context).scheduleNext(time)
            }
        }
    }

    companion object {
        const val ACTION_REMINDER_FIRED = "com.moodpatterndiary.app.action.REMINDER_FIRED"
        const val EXTRA_REMINDER_MINUTE_OF_DAY = "reminder_minute_of_day"
    }
}
