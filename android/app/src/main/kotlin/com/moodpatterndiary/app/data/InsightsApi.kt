package com.moodpatterndiary.app.data

import com.moodpatterndiary.app.domain.FeelingCatalog
import com.moodpatterndiary.app.domain.InsightsResult
import com.moodpatterndiary.app.domain.Pattern
import com.moodpatterndiary.app.domain.PatternDirection
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import retrofit2.http.GET
import java.time.Instant

@Serializable
data class PatternDto(
    val id: String,
    val topic: String,
    val feeling: String,
    @SerialName("occurrence_count") val occurrenceCount: Int,
    val direction: String,
    @SerialName("narrative_text") val narrativeText: String,
    @SerialName("suggestion_text") val suggestionText: String,
    @SerialName("last_updated_at") val lastUpdatedAt: String,
)

@Serializable
data class InsightsResponse(
    val patterns: List<PatternDto> = emptyList(),
    @SerialName("insufficient_data") val insufficientData: Boolean = false,
)

/** Retrofit interface for contracts/api.md's `GET /insights`. */
interface InsightsApi {
    @GET("insights")
    suspend fun getInsights(): InsightsResponse
}

class InsightsRepository(
    private val api: InsightsApi,
    private val feelings: FeelingRepository = NetworkModule.feelingRepository,
) {
    suspend fun getInsights(): ApiResult<InsightsResult> =
        feelings.withCatalog { catalog ->
            safeApiCall {
                val response = api.getInsights()
                InsightsResult(
                    patterns = response.patterns.map { it.toDomain(catalog) },
                    insufficientData = response.insufficientData,
                )
            }
        }
}

private fun PatternDto.toDomain(catalog: FeelingCatalog): Pattern =
    Pattern(
        id = id,
        topic = topic,
        feeling = catalog.fromKey(feeling),
        occurrenceCount = occurrenceCount,
        direction = if (direction == "change") PatternDirection.CHANGE else PatternDirection.KEEP,
        narrativeText = narrativeText,
        suggestionText = suggestionText,
        lastUpdatedAt = runCatching { Instant.parse(lastUpdatedAt) }.getOrDefault(Instant.EPOCH),
    )
