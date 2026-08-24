package com.moodpatterndiary.app.domain

import java.time.Instant

/** Whether the suggestion tied to a pattern is to change the habit or keep it (FR-011). */
enum class PatternDirection {
    KEEP,
    CHANGE,
}

/** A detected, threshold-confirmed Topic-Feeling correlation returned by `GET /insights`. */
data class Pattern(
    val id: String,
    val topic: String,
    val feeling: Feeling?,
    val occurrenceCount: Int,
    val direction: PatternDirection,
    val narrativeText: String,
    val suggestionText: String,
    val lastUpdatedAt: Instant,
)

/** Wraps `GET /insights`' response, including the "not enough data yet" empty state (FR-012, US3 AC4). */
data class InsightsResult(
    val patterns: List<Pattern>,
    val insufficientData: Boolean,
)
