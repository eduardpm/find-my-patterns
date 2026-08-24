package com.moodpatterndiary.app.data

import com.moodpatterndiary.app.domain.Valence
import kotlinx.coroutines.runBlocking
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import retrofit2.HttpException
import retrofit2.Response
import java.time.LocalDate

/**
 * T040 — proves [EntryRepository] turns the backend's `409 stale_entry`
 * (specs/003-web-client/contracts/api.md) into [ApiResult.StaleEntry], carrying the parsed
 * `current` entry, and that this is distinguishable from an ordinary server error.
 *
 * That distinction is the whole point of FR-011/FR-023: a generic error means "try again", while a
 * stale-entry result means "your view was out of date, here is what's actually stored, choose what
 * happens to what you wrote". A screen cannot offer retry/discard/carry-across if the repository
 * has flattened the conflict into an error string.
 *
 * Pure JVM test — no Android framework, no network. Fakes stand in for the two Retrofit
 * interfaces, so the assertions are about mapping, not about transport.
 */
class ConflictMappingTest {
    // --- Fakes -------------------------------------------------------------------------------

    /** The feeling set the client would have fetched from `GET /feelings` (T044/T045). */
    private class FakeFeelingApi : FeelingApi {
        override suspend fun getFeelings(): FeelingListResponse =
            FeelingListResponse(
                feelings =
                    listOf(
                        FeelingDto(key = "happy", label = "Happy", valence = "positive"),
                        FeelingDto(key = "neutral", label = "Neutral", valence = "neutral"),
                        FeelingDto(key = "sad", label = "Sad", valence = "negative"),
                    ),
            )
    }

    /** Replays a canned outcome for the one mutating call under test, and records what was sent. */
    private class FakeEntryApi(
        private val failWith: HttpException? = null,
        private val deleteResponse: Response<Unit> = Response.success(null),
    ) : EntryApi {
        var lastUpdateRequest: EntryUpdateRequest? = null
        var lastDeleteVersion: Int? = null

        override suspend fun createEntry(request: EntryCreateRequest): EntryDto = unused()

        override suspend fun updateEntry(
            id: String,
            request: EntryUpdateRequest,
        ): EntryDto {
            lastUpdateRequest = request
            throw failWith ?: unused()
        }

        override suspend fun deleteEntry(
            id: String,
            version: Int,
        ): Response<Unit> {
            lastDeleteVersion = version
            return deleteResponse
        }

        override suspend fun listEntries(date: String): EntryListResponse = unused()

        private fun unused(): Nothing = throw IllegalStateException("not exercised by this test")
    }

    // --- Fixtures ----------------------------------------------------------------------------

    private val staleBody =
        """
        {
          "error": {
            "code": "stale_entry",
            "message": "This entry was changed somewhere else since you loaded it."
          },
          "current": {
            "id": "11111111-2222-3333-4444-555555555555",
            "created_at": "2026-07-28T13:05:00Z",
            "entry_date": "2026-07-28",
            "mode": "freeform",
            "raw_text": "the version that is actually stored",
            "feeling_key": "happy",
            "feeling_source": "confirmed",
            "version": 4
          }
        }
        """.trimIndent()

    private fun httpError(
        code: Int,
        body: String,
    ): HttpException = HttpException(Response.error<Unit>(code, body.toResponseBody(JSON)))

    private fun repository(api: FakeEntryApi) = EntryRepository(api, FeelingRepository(FakeFeelingApi()))

    // --- Tests -------------------------------------------------------------------------------

    @Test
    @DisplayName("a 409 on PATCH becomes a stale-entry result carrying the parsed current entry")
    fun patchConflictMapsToStaleEntryWithCurrent() =
        runBlocking {
            val api = FakeEntryApi(failWith = httpError(409, staleBody))

            val result = repository(api).updateEntry(entryId = "entry-1", version = 2, text = "my edit", feeling = null)

            val stale = result as? ApiResult.StaleEntry
            assertNotNull(stale, "expected ApiResult.StaleEntry, got $result")
            requireNotNull(stale)

            assertEquals("This entry was changed somewhere else since you loaded it.", stale.message)
            assertEquals("11111111-2222-3333-4444-555555555555", stale.current.id)
            assertEquals("the version that is actually stored", stale.current.rawText)
            assertEquals(LocalDate.of(2026, 7, 28), stale.current.entryDate)
            // `current.version` is what a retry must be sent with (contract guarantee 3).
            assertEquals(4, stale.current.version)
        }

    @Test
    @DisplayName("the current entry's feeling is resolved through the backend-served feeling set")
    fun staleCurrentEntryResolvesFeelingFromCatalog() =
        runBlocking {
            val api = FakeEntryApi(failWith = httpError(409, staleBody))

            val result = repository(api).updateEntry(entryId = "entry-1", version = 2, text = "my edit", feeling = null)
            val stale = result as ApiResult.StaleEntry

            assertEquals("happy", stale.current.feeling?.key)
            assertEquals("Happy", stale.current.feeling?.label)
            assertEquals(Valence.POSITIVE, stale.current.feeling?.valence)
        }

    @Test
    @DisplayName("a stale-entry result is distinguishable from a generic server error")
    fun staleEntryIsDistinguishableFromGenericError() =
        runBlocking {
            val conflict =
                repository(FakeEntryApi(failWith = httpError(409, staleBody)))
                    .updateEntry(entryId = "entry-1", version = 2, text = "my edit", feeling = null)

            val serverError =
                repository(FakeEntryApi(failWith = httpError(500, """{"error":{"code":"error","message":"boom"}}""")))
                    .updateEntry(entryId = "entry-1", version = 2, text = "my edit", feeling = null)

            assertTrue(conflict is ApiResult.StaleEntry, "409 should map to StaleEntry")
            assertTrue(serverError is ApiResult.Error, "500 should map to a plain Error")
            assertFalse(serverError is ApiResult.StaleEntry, "500 must not be mistaken for a conflict")

            // StaleEntry is deliberately a subtype of Error so screens that don't handle conflicts
            // yet still show the message rather than silently reporting success -- but a screen
            // that does handle them can always tell the two apart by type.
            assertTrue(conflict is ApiResult.Error, "StaleEntry should still satisfy `is Error`")
            assertNull((serverError as ApiResult.Error).let { it as? ApiResult.StaleEntry })
        }

    @Test
    @DisplayName("a 409 on DELETE also becomes a stale-entry result, and nothing is reported deleted")
    fun deleteConflictMapsToStaleEntry() =
        runBlocking {
            val api =
                FakeEntryApi(
                    deleteResponse = Response.error(409, staleBody.toResponseBody(JSON)),
                )

            val result = repository(api).deleteEntry(entryId = "entry-1", version = 2)

            // FR-021: nothing was deleted, so this must not read as a success.
            assertFalse(result is ApiResult.Success, "a rejected delete must not look like a success")

            val stale = result as? ApiResult.StaleEntry
            assertNotNull(stale, "expected ApiResult.StaleEntry, got $result")
            requireNotNull(stale)
            assertEquals(4, stale.current.version)
        }

    @Test
    @DisplayName("the version the caller read is sent on PATCH (body) and DELETE (query)")
    fun versionIsSentOnBothMutations() =
        runBlocking {
            val patchApi = FakeEntryApi(failWith = httpError(409, staleBody))
            repository(patchApi).updateEntry(entryId = "entry-1", version = 7, text = "my edit", feeling = null)
            assertEquals(7, patchApi.lastUpdateRequest?.version)

            val deleteApi = FakeEntryApi()
            repository(deleteApi).deleteEntry(entryId = "entry-1", version = 9)
            assertEquals(9, deleteApi.lastDeleteVersion)
        }

    @Test
    @DisplayName("a 409 whose body can't be parsed still fails, without inventing a current entry")
    fun unparseableConflictFallsBackToPlainError() =
        runBlocking {
            val api = FakeEntryApi(failWith = httpError(409, "not json at all"))

            val result = repository(api).updateEntry(entryId = "entry-1", version = 2, text = "my edit", feeling = null)

            assertTrue(result is ApiResult.Error)
            assertFalse(result is ApiResult.StaleEntry, "no `current` means no side-by-side comparison to offer")
        }

    private companion object {
        private val JSON = "application/json".toMediaType()
    }
}
