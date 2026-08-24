package com.moodpatterndiary.app.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

// --- Wire types, matching contracts/api.md's `/entries` section exactly. ---

@Serializable
data class GuidedAnswerRequest(
    @SerialName("question_key") val questionKey: String,
    @SerialName("answer_text") val answerText: String,
)

@Serializable
data class EntryCreateRequest(
    val mode: String,
    @SerialName("raw_text") val rawText: String = "",
    @SerialName("guided_answers") val guidedAnswers: List<GuidedAnswerRequest> = emptyList(),
)

@Serializable
data class EntryUpdateRequest(
    // Required by 003 contracts/api.md: the version the client last read. Omitting it is a 422 --
    // the backend has no way to tell a deliberate edit from one based on a stale view (FR-011).
    val version: Int,
    @SerialName("raw_text") val rawText: String? = null,
    @SerialName("feeling_key") val feelingKey: String? = null,
)

@Serializable
data class SuggestedFeelingDto(
    val key: String,
    val confidence: Double,
)

@Serializable
data class EntryDto(
    val id: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("entry_date") val entryDate: String,
    val mode: String,
    @SerialName("raw_text") val rawText: String,
    @SerialName("feeling_key") val feelingKey: String? = null,
    @SerialName("feeling_source") val feelingSource: String,
    @SerialName("suggested_feeling") val suggestedFeeling: SuggestedFeelingDto? = null,
    // The entry revision marker (FR-011). Present on every entry-bearing response in 003's
    // contract; no default, so a backend that stopped sending it fails loudly rather than
    // silently sending version 0 back and conflicting on every edit.
    val version: Int,
)

@Serializable
data class EntryListResponse(
    val entries: List<EntryDto> = emptyList(),
)

/**
 * The `409 stale_entry` body (003 contracts/api.md). `current` is a sibling of the standard
 * `error` envelope and carries the entry as actually stored, which is what lets FR-023's
 * side-by-side comparison render without a second round trip.
 */
@Serializable
data class StaleEntryResponse(
    val error: ErrorDetailDto,
    val current: EntryDto,
)

/** Retrofit interface for contracts/api.md's `/entries` endpoints. */
interface EntryApi {
    @POST("entries")
    suspend fun createEntry(
        @Body request: EntryCreateRequest,
    ): EntryDto

    @PATCH("entries/{id}")
    suspend fun updateEntry(
        @Path("id") id: String,
        @Body request: EntryUpdateRequest,
    ): EntryDto

    // Backend returns 204 No Content; Retrofit special-cases 204/205 by skipping body
    // conversion entirely, so this must be Response<Unit> rather than a bare suspend Unit
    // return (which would NPE trying to unwrap a null body). See EntryRepository.deleteEntry.
    //
    // `version` rides as a query parameter, not a body: DELETE bodies are unreliably supported
    // (003 research.md §3), so the contract puts it in the URL.
    @DELETE("entries/{id}")
    suspend fun deleteEntry(
        @Path("id") id: String,
        @Query("version") version: Int,
    ): Response<Unit>

    @GET("entries")
    suspend fun listEntries(
        @Query("date") date: String,
    ): EntryListResponse
}
