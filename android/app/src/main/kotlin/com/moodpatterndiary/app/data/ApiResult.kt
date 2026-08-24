package com.moodpatterndiary.app.data

import com.moodpatterndiary.app.domain.Entry
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import retrofit2.HttpException
import java.io.IOException
import java.net.ConnectException
import java.net.UnknownHostException

/**
 * Uniform result wrapper for every network call in the app. FR-020 requires that a failed
 * network call show a clear "can't reach the diary server" message instead of crashing or
 * failing silently — every repository funnels its Retrofit calls through [safeApiCall] so the
 * UI layer only ever has to handle [ApiResult.Success] / [ApiResult.Error].
 */
sealed interface ApiResult<out T> {
    data class Success<T>(val data: T) : ApiResult<T>

    open class Error(val message: String, val cause: Throwable? = null) : ApiResult<Nothing> {
        override fun toString(): String = "Error(message=$message, cause=$cause)"
    }

    /**
     * The mutation was rejected because it was based on a version of the entry that is no longer
     * current — the backend's `409 stale_entry` (FR-011, 003 contracts/api.md). Nothing was
     * changed on the server, and [current] is the entry **as actually stored**, parsed out of the
     * conflict body so the screen can show FR-023's side-by-side comparison and offer
     * retry/discard/carry-across without a second round trip.
     *
     * It is deliberately a *subtype* of [Error] rather than a third arm of [ApiResult]: a screen
     * that hasn't been taught about conflicts yet still falls into its `is Error` branch and shows
     * the explanatory message instead of silently succeeding. Screens that do handle it must match
     * `is ApiResult.StaleEntry` **before** `is ApiResult.Error`, since the first matching branch of
     * a `when` wins.
     */
    class StaleEntry(
        message: String,
        val current: Entry,
        cause: Throwable? = null,
    ) : Error(message, cause) {
        override fun toString(): String = "StaleEntry(message=$message, current=$current)"
    }
}

@Serializable
data class ErrorDetailDto(val code: String, val message: String)

@Serializable
data class ErrorResponseDto(val error: ErrorDetailDto)

private val errorJson = Json { ignoreUnknownKeys = true }

/**
 * Runs [block], turning anything that goes wrong into an [ApiResult.Error] with a message a person
 * can act on (FR-020).
 *
 * [onHttpError] lets a caller claim specific HTTP status codes that mean something richer than
 * "the server said no" — [EntryRepository] uses it to turn a `409` into [ApiResult.StaleEntry].
 * A handler that returns `null` declines the error and it falls through to the default message.
 * A handler that claims an error **must** consume the error body itself: the body is a one-shot
 * stream, so it can only be read once.
 */
suspend fun <T> safeApiCall(
    onHttpError: ((HttpException) -> ApiResult<T>?)? = null,
    block: suspend () -> T,
): ApiResult<T> {
    return try {
        ApiResult.Success(block())
    } catch (e: CancellationException) {
        // Never swallow coroutine cancellation (e.g. the screen was closed mid-request).
        throw e
    } catch (e: BackendNotConfiguredException) {
        ApiResult.Error("Set up your backend's address in Settings before creating or viewing entries.", e)
    } catch (e: UnknownHostException) {
        ApiResult.Error("Can't reach the diary server. Check the address in Settings and that you're on the same network.", e)
    } catch (e: ConnectException) {
        ApiResult.Error("Can't reach the diary server. Make sure the backend is running and reachable.", e)
    } catch (e: IOException) {
        ApiResult.Error("Can't reach the diary server. Check your connection and try again.", e)
    } catch (e: HttpException) {
        onHttpError?.invoke(e) ?: ApiResult.Error(e.toFriendlyMessage(), e)
    } catch (e: Exception) {
        ApiResult.Error("Something went wrong: ${e.message ?: "unknown error"}.", e)
    }
}

private fun HttpException.toFriendlyMessage(): String {
    val body = response()?.errorBody()?.string()
    val parsedMessage =
        body?.let {
            runCatching { errorJson.decodeFromString(ErrorResponseDto.serializer(), it).error.message }.getOrNull()
        }
    return parsedMessage ?: "The diary server returned an error (code ${code()})."
}
