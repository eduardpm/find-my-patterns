package com.moodpatterndiary.app.data

import com.moodpatterndiary.app.domain.GuidingQuestion
import com.moodpatterndiary.app.domain.QuestionCategory
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import retrofit2.http.GET

@Serializable
data class GuidingQuestionDto(
    val key: String,
    val category: String,
    @SerialName("prompt_text") val promptText: String,
    @SerialName("trigger_keywords") val triggerKeywords: List<String> = emptyList(),
    @SerialName("is_mandatory") val isMandatory: Boolean = false,
)

@Serializable
data class GuidingQuestionListResponse(
    val questions: List<GuidingQuestionDto> = emptyList(),
)

/** Retrofit interface for contracts/api.md's `GET /guiding-questions`. */
interface GuidingQuestionApi {
    @GET("guiding-questions")
    suspend fun getGuidingQuestions(): GuidingQuestionListResponse
}

/**
 * Fetches and caches the guiding-question library in memory for the life of the process
 * (research.md §1: "The app fetches and caches the whole library once") so
 * [com.moodpatterndiary.app.domain.QuestionTrigger] can match against it without a network call
 * on every entry-composer open.
 */
class GuidingQuestionRepository(private val api: GuidingQuestionApi) {
    @Volatile
    private var cached: List<GuidingQuestion>? = null
    private val loadMutex = Mutex()

    suspend fun getQuestions(forceRefresh: Boolean = false): ApiResult<List<GuidingQuestion>> {
        cached?.let { if (!forceRefresh) return ApiResult.Success(it) }

        return loadMutex.withLock {
            cached?.let { if (!forceRefresh) return@withLock ApiResult.Success(it) }
            val result = safeApiCall { api.getGuidingQuestions().questions.map { it.toDomain() } }
            if (result is ApiResult.Success) cached = result.data
            result
        }
    }
}

private fun GuidingQuestionDto.toDomain(): GuidingQuestion =
    GuidingQuestion(
        key = key,
        category =
            when (category) {
                "general" -> QuestionCategory.GENERAL
                "mind_body" -> QuestionCategory.MIND_BODY
                "small_influences" -> QuestionCategory.SMALL_INFLUENCES
                "response_outcome" -> QuestionCategory.RESPONSE_OUTCOME
                else -> QuestionCategory.UNKNOWN
            },
        promptText = promptText,
        triggerKeywords = triggerKeywords,
        isMandatory = isMandatory,
    )
