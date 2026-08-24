package com.moodpatterndiary.app.data

import com.moodpatterndiary.app.domain.DaySummary
import com.moodpatterndiary.app.domain.FeelingCatalog
import com.moodpatterndiary.app.domain.MonthlySummary
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import retrofit2.http.GET
import retrofit2.http.Query
import java.time.LocalDate
import java.time.YearMonth

@Serializable
data class DaySummaryDto(
    val date: String,
    val feelings: List<String> = emptyList(),
)

@Serializable
data class MonthlySummaryDto(
    val month: String,
    val days: List<DaySummaryDto> = emptyList(),
    @SerialName("totals_by_feeling") val totalsByFeeling: Map<String, Int> = emptyMap(),
    @SerialName("average_entries_per_day") val averageEntriesPerDay: Double = 0.0,
)

/** Retrofit interface for contracts/api.md's `GET /monthly-summary`. */
interface MonthlySummaryApi {
    @GET("monthly-summary")
    suspend fun getMonthlySummary(
        @Query("month") month: String,
    ): MonthlySummaryDto
}

class MonthlySummaryRepository(
    private val api: MonthlySummaryApi,
    private val feelings: FeelingRepository = NetworkModule.feelingRepository,
) {
    suspend fun getSummary(month: YearMonth): ApiResult<MonthlySummary> =
        feelings.withCatalog { catalog ->
            safeApiCall {
                api.getMonthlySummary(month.toString()).toDomain(catalog)
            }
        }
}

private fun MonthlySummaryDto.toDomain(catalog: FeelingCatalog): MonthlySummary =
    MonthlySummary(
        month = runCatching { YearMonth.parse(month) }.getOrDefault(YearMonth.now()),
        days = days.map { it.toDomain(catalog) },
        // Built by walking the catalog rather than the response so the totals panel lists feelings
        // in the backend's own (stable) order without the UI having to know what that order is.
        totalsByFeeling =
            catalog.feelings.mapNotNull { feeling ->
                totalsByFeeling[feeling.key]?.let { feeling to it }
            }.toMap(),
        averageEntriesPerDay = averageEntriesPerDay,
    )

private fun DaySummaryDto.toDomain(catalog: FeelingCatalog): DaySummary =
    DaySummary(
        date = LocalDate.parse(date),
        feelings = feelings.mapNotNull { catalog.fromKey(it) },
    )
