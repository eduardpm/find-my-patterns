package com.moodpatterndiary.app.data

import com.moodpatterndiary.app.domain.Entry
import com.moodpatterndiary.app.domain.EntryMode
import com.moodpatterndiary.app.domain.Feeling
import com.moodpatterndiary.app.domain.FeelingCatalog
import com.moodpatterndiary.app.domain.FeelingSource
import com.moodpatterndiary.app.domain.GuidingQuestionAnswer
import com.moodpatterndiary.app.domain.SuggestedFeeling
import kotlinx.serialization.json.Json
import retrofit2.HttpException
import java.net.HttpURLConnection
import java.time.Instant
import java.time.LocalDate

/**
 * Talks to `POST/PATCH/DELETE/GET /entries` (contracts/api.md) and maps wire DTOs onto the
 * domain [Entry] model used by the UI. Every call goes through [safeApiCall] so failures surface
 * as a user-facing message (FR-020) rather than an exception reaching a screen.
 *
 * Mutations additionally carry the [Entry.version] they were based on and translate the backend's
 * `409` into [ApiResult.StaleEntry] (FR-011/FR-022), so a screen can tell "your view was out of
 * date, here is what's actually stored" apart from an ordinary server error.
 *
 * [feelings] defaults to the shared process-wide catalog; it is a parameter so tests can supply a
 * fixed feeling set without touching the network stack.
 */
class EntryRepository(
    private val api: EntryApi,
    private val feelings: FeelingRepository = NetworkModule.feelingRepository,
) {
    suspend fun createFreeformEntry(text: String): ApiResult<Entry> =
        feelings.withCatalog { catalog ->
            safeApiCall {
                api.createEntry(EntryCreateRequest(mode = "freeform", rawText = text)).toDomain(catalog)
            }
        }

    suspend fun createGuidedEntry(
        answers: List<GuidingQuestionAnswer>,
        combinedText: String,
    ): ApiResult<Entry> =
        feelings.withCatalog { catalog ->
            safeApiCall {
                api.createEntry(
                    EntryCreateRequest(
                        mode = "guided",
                        rawText = combinedText,
                        guidedAnswers = answers.map { GuidedAnswerRequest(it.questionKey, it.answerText) },
                    ),
                ).toDomain(catalog)
            }
        }

    /** Confirms or overrides the suggested feeling for an entry (FR-007). */
    suspend fun confirmFeeling(
        entryId: String,
        version: Int,
        feeling: Feeling,
    ): ApiResult<Entry> = patch(entryId, EntryUpdateRequest(version = version, feelingKey = feeling.key))

    /** General edit: either field may be omitted to leave it unchanged (FR-008). */
    suspend fun updateEntry(
        entryId: String,
        version: Int,
        text: String?,
        feeling: Feeling?,
    ): ApiResult<Entry> = patch(entryId, EntryUpdateRequest(version = version, rawText = text, feelingKey = feeling?.key))

    /**
     * Deletes the entry the caller last read. A [version] that is no longer current comes back as
     * [ApiResult.StaleEntry] and nothing is deleted (FR-021) — the caller decides whether to
     * delete the version it has now been shown.
     */
    suspend fun deleteEntry(
        entryId: String,
        version: Int,
    ): ApiResult<Unit> =
        feelings.withCatalog { catalog ->
            safeApiCall(onHttpError = { it.toConflictResult(catalog) }) {
                val response = api.deleteEntry(entryId, version)
                if (!response.isSuccessful) {
                    throw HttpException(response)
                }
            }
        }

    suspend fun listEntries(date: LocalDate): ApiResult<List<Entry>> =
        feelings.withCatalog { catalog ->
            safeApiCall {
                api.listEntries(date.toString()).entries.map { it.toDomain(catalog) }
            }
        }

    private suspend fun patch(
        entryId: String,
        request: EntryUpdateRequest,
    ): ApiResult<Entry> =
        feelings.withCatalog { catalog ->
            safeApiCall(onHttpError = { it.toConflictResult(catalog) }) {
                api.updateEntry(entryId, request).toDomain(catalog)
            }
        }
}

private val conflictJson = Json { ignoreUnknownKeys = true }

/**
 * Claims every `409` so that a stale-version rejection becomes [ApiResult.StaleEntry] rather than
 * a generic error (FR-011). Returns `null` for any other status, letting [safeApiCall] apply its
 * usual message.
 *
 * The whole `409` case is handled here on purpose: the error body is a one-shot stream, so once
 * this function has read it, [safeApiCall]'s default path could not read it again.
 */
private fun HttpException.toConflictResult(catalog: FeelingCatalog): ApiResult<Nothing>? {
    if (code() != HttpURLConnection.HTTP_CONFLICT) return null

    val body = runCatching { response()?.errorBody()?.string() }.getOrNull()
    val parsed =
        body?.let { raw ->
            runCatching { conflictJson.decodeFromString(StaleEntryResponse.serializer(), raw) }.getOrNull()
        }

    return if (parsed != null) {
        ApiResult.StaleEntry(
            message = parsed.error.message,
            current = parsed.current.toDomain(catalog),
            cause = this,
        )
    } else {
        // A 409 whose body we couldn't read is still a conflict, just without the comparison.
        ApiResult.Error("This entry was changed somewhere else since you loaded it.", this)
    }
}

private fun EntryDto.toDomain(catalog: FeelingCatalog): Entry =
    Entry(
        id = id,
        createdAt = runCatching { Instant.parse(createdAt) }.getOrDefault(Instant.EPOCH),
        entryDate = LocalDate.parse(entryDate),
        mode = if (mode == "guided") EntryMode.GUIDED else EntryMode.FREEFORM,
        rawText = rawText,
        feeling = catalog.fromKey(feelingKey),
        feelingSource =
            when (feelingSource) {
                "suggested" -> FeelingSource.SUGGESTED
                "confirmed" -> FeelingSource.CONFIRMED
                "overridden" -> FeelingSource.OVERRIDDEN
                else -> FeelingSource.UNSET
            },
        suggestedFeeling =
            suggestedFeeling?.let { dto ->
                catalog.fromKey(dto.key)?.let { feeling -> SuggestedFeeling(feeling, dto.confidence) }
            },
        version = version,
    )
