package com.moodpatterndiary.app.domain

import java.time.LocalDate
import java.time.YearMonth

/** Per-day breakdown for the monthly calendar grid (FR-015). */
data class DaySummary(
    val date: LocalDate,
    val feelings: List<Feeling>,
)

/** Powers the monthly calendar screen (FR-015/FR-016), from `GET /monthly-summary`. */
data class MonthlySummary(
    val month: YearMonth,
    val days: List<DaySummary>,
    val totalsByFeeling: Map<Feeling, Int>,
    val averageEntriesPerDay: Double,
)
