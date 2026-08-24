package com.moodpatterndiary.app.domain

/**
 * Client-side keyword matching against the draft entry text (research.md §1): decides which
 * optional guiding questions to surface next, entirely on-device and with zero network calls
 * while the user is typing — the guiding-question library itself is fetched and cached once
 * ([com.moodpatterndiary.app.data.GuidingQuestionRepository]), so this is pure, synchronous,
 * local logic on every keystroke.
 */
object QuestionTrigger {
    private val wordSplitRegex = Regex("[^\\p{L}\\p{Nd}']+")

    /**
     * Returns up to [maxCount] non-mandatory questions from [library] whose
     * [GuidingQuestion.triggerKeywords] appear in [draftText], in library order. Mandatory
     * questions (the single general prompt) are never included here — the caller always shows
     * that one first, per research.md §1.
     */
    fun matchingOptionalQuestions(
        draftText: String,
        library: List<GuidingQuestion>,
        maxCount: Int = 2,
    ): List<GuidingQuestion> {
        if (draftText.isBlank() || library.isEmpty()) return emptyList()

        val lowerText = draftText.lowercase()
        val words = lowerText.split(wordSplitRegex).filterTo(HashSet()) { it.isNotBlank() }

        return library
            .asSequence()
            .filter { !it.isMandatory }
            .filter { question ->
                question.triggerKeywords.any { keyword ->
                    val lowerKeyword = keyword.lowercase()
                    lowerKeyword.isNotBlank() && (words.contains(lowerKeyword) || lowerText.contains(lowerKeyword))
                }
            }
            .take(maxCount)
            .toList()
    }
}
