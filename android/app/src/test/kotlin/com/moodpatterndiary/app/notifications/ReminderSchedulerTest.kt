package com.moodpatterndiary.app.notifications

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import java.time.Clock
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneOffset

/**
 * Pure-logic unit test for [ReminderScheduler.nextTriggerMillis] (T057) -- the one Android test
 * called out in tasks.md/plan.md as worth writing despite the "UI is not test-gated" rule,
 * since it's deterministic, non-UI scheduling math with no Android framework dependency. Runs on
 * the plain JVM (no Robolectric/instrumentation needed): [ReminderScheduler] itself references
 * Android types, but this test only ever calls the companion object's pure function.
 */
class ReminderSchedulerTest {
    private val zone = ZoneOffset.UTC

    private fun clockAt(isoLocalDateTime: String): Clock {
        val instant = LocalDateTime.parse(isoLocalDateTime).atZone(zone).toInstant()
        return Clock.fixed(instant, zone)
    }

    private fun epochMillisOf(
        date: LocalDate,
        time: LocalTime,
    ): Long = LocalDateTime.of(date, time).atZone(zone).toInstant().toEpochMilli()

    @Test
    @DisplayName("returns today's trigger time when the target time hasn't passed yet")
    fun schedulesLaterTodayWhenTimeHasNotPassed() {
        val clock = clockAt("2026-07-27T08:00:00")
        val expected = epochMillisOf(LocalDate.of(2026, 7, 27), LocalTime.of(9, 0))

        val actual = ReminderScheduler.nextTriggerMillis(LocalTime.of(9, 0), clock)

        assertEquals(expected, actual)
    }

    @Test
    @DisplayName("rolls over to tomorrow when the target time already passed today")
    fun schedulesTomorrowWhenTimeAlreadyPassed() {
        val clock = clockAt("2026-07-27T13:00:00")
        val expected = epochMillisOf(LocalDate.of(2026, 7, 28), LocalTime.of(9, 0))

        val actual = ReminderScheduler.nextTriggerMillis(LocalTime.of(9, 0), clock)

        assertEquals(expected, actual)
    }

    @Test
    @DisplayName("rolls over to tomorrow when now is exactly the target time")
    fun schedulesTomorrowWhenNowExactlyEqualsTargetTime() {
        val clock = clockAt("2026-07-27T09:00:00")
        val expected = epochMillisOf(LocalDate.of(2026, 7, 28), LocalTime.of(9, 0))

        val actual = ReminderScheduler.nextTriggerMillis(LocalTime.of(9, 0), clock)

        assertEquals(expected, actual)
    }

    @Test
    @DisplayName("computes an independent next-fire time for each of the four daily reminder slots")
    fun computesCorrectNextTriggerForEachDailyReminderTime() {
        val clock = clockAt("2026-07-27T10:30:00")
        val today = LocalDate.of(2026, 7, 27)
        val tomorrow = today.plusDays(1)

        assertEquals(
            epochMillisOf(tomorrow, LocalTime.of(9, 0)),
            ReminderScheduler.nextTriggerMillis(LocalTime.of(9, 0), clock),
        )
        assertEquals(
            epochMillisOf(today, LocalTime.of(12, 0)),
            ReminderScheduler.nextTriggerMillis(LocalTime.of(12, 0), clock),
        )
        assertEquals(
            epochMillisOf(today, LocalTime.of(18, 0)),
            ReminderScheduler.nextTriggerMillis(LocalTime.of(18, 0), clock),
        )
        assertEquals(
            epochMillisOf(today, LocalTime.of(21, 0)),
            ReminderScheduler.nextTriggerMillis(LocalTime.of(21, 0), clock),
        )
    }

    @Test
    @DisplayName("handles a month/year rollover correctly")
    fun handlesMonthRollover() {
        val clock = clockAt("2026-07-31T22:00:00")
        val expected = epochMillisOf(LocalDate.of(2026, 8, 1), LocalTime.of(9, 0))

        val actual = ReminderScheduler.nextTriggerMillis(LocalTime.of(9, 0), clock)

        assertEquals(expected, actual)
    }

    @Test
    @DisplayName("REMINDER_TIMES contains exactly the four spec-required daily times, in order")
    fun reminderTimesMatchSpec() {
        val expected =
            listOf(
                LocalTime.of(9, 0),
                LocalTime.of(12, 0),
                LocalTime.of(18, 0),
                LocalTime.of(21, 0),
            )

        assertEquals(expected, ReminderScheduler.REMINDER_TIMES)
    }
}
