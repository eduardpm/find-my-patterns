package com.moodpatterndiary.app.domain

import java.time.Instant
import java.time.LocalDate

/** Which flow produced the entry (FR-004/FR-005). */
enum class EntryMode {
    GUIDED,
    FREEFORM,
}

/** Tracks the hybrid suggest/confirm flow in FR-007. */
enum class FeelingSource {
    SUGGESTED,
    CONFIRMED,
    OVERRIDDEN,
    UNSET,
}

data class SuggestedFeeling(
    val feeling: Feeling,
    val confidence: Double,
)

/**
 * A single diary entry (data-model.md `DiaryEntry`). Entries are never merged (FR-002) — each
 * has its own id and timestamp even if several exist on the same [entryDate].
 */
data class Entry(
    val id: String,
    val createdAt: Instant,
    val entryDate: LocalDate,
    val mode: EntryMode,
    val rawText: String,
    val feeling: Feeling?,
    val feelingSource: FeelingSource,
    val suggestedFeeling: SuggestedFeeling?,
    /**
     * The entry revision marker (FR-011/FR-022). Carries no diary content — it exists so an edit
     * or delete can say which version of the entry it was based on, and so the backend can reject
     * a change made from a view that another client has already moved past. Every mutation must
     * send back the version it read; a mismatch comes back as `409` and
     * [com.moodpatterndiary.app.data.ApiResult.StaleEntry].
     */
    val version: Int,
)
