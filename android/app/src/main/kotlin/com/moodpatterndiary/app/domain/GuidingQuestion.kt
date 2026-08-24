package com.moodpatterndiary.app.domain

/** Mirrors the backend's `GuidingQuestion.category` enum (data-model.md). */
enum class QuestionCategory {
    GENERAL,
    MIND_BODY,
    SMALL_INFLUENCES,
    RESPONSE_OUTCOME,
    UNKNOWN,
}

/**
 * A predefined prompt shown during entry creation (FR-004/FR-006). The whole library is fetched
 * once via `GET /guiding-questions` and cached client-side (research.md §1) — [triggerKeywords]
 * drives which optional prompts [com.moodpatterndiary.app.domain.QuestionTrigger] surfaces while
 * the user types, with zero additional network calls.
 */
data class GuidingQuestion(
    val key: String,
    val category: QuestionCategory,
    val promptText: String,
    val triggerKeywords: List<String>,
    val isMandatory: Boolean,
)

/** One answered prompt, ready to submit as part of `POST /entries`' `guided_answers`. */
data class GuidingQuestionAnswer(
    val questionKey: String,
    val answerText: String,
)
