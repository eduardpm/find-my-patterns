package com.moodpatterndiary.app.data

import com.moodpatterndiary.app.domain.Feeling
import com.moodpatterndiary.app.domain.FeelingCatalog
import com.moodpatterndiary.app.domain.Valence
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import retrofit2.http.GET

@Serializable
data class FeelingDto(
    val key: String,
    val label: String,
    val valence: String,
)

@Serializable
data class FeelingListResponse(
    val feelings: List<FeelingDto> = emptyList(),
)

/** Retrofit interface for 003 contracts/api.md's `GET /feelings`. */
interface FeelingApi {
    @GET("feelings")
    suspend fun getFeelings(): FeelingListResponse
}

/**
 * Fetches and caches the predefined feeling set for the life of the process, the same way
 * [GuidingQuestionRepository] caches the guiding-question library.
 *
 * This is what closes constitution Principle VII for the Android client: the set's keys, labels
 * and valences are the backend's to define, and every screen and mapper now reads them from here
 * instead of from a hardcoded enum. The set is fixed in v1, so one fetch per process is plenty.
 */
class FeelingRepository(private val api: FeelingApi) {
    @Volatile
    private var cached: FeelingCatalog? = null
    private val loadMutex = Mutex()

    /** The feeling set for display, e.g. by `FeelingChipRow`. */
    suspend fun getFeelings(forceRefresh: Boolean = false): ApiResult<List<Feeling>> =
        when (val result = getCatalog(forceRefresh)) {
            is ApiResult.Success -> ApiResult.Success(result.data.feelings)
            is ApiResult.Error -> result
        }

    /** The feeling set as a lookup, for mapping wire `feeling_key`s onto the domain model. */
    suspend fun getCatalog(forceRefresh: Boolean = false): ApiResult<FeelingCatalog> {
        cached?.let { if (!forceRefresh) return ApiResult.Success(it) }

        return loadMutex.withLock {
            cached?.let { if (!forceRefresh) return@withLock ApiResult.Success(it) }
            val result = safeApiCall { FeelingCatalog(api.getFeelings().feelings.map { it.toDomain() }) }
            if (result is ApiResult.Success) cached = result.data
            result
        }
    }
}

/**
 * Loads the feeling catalog, then runs [block] with it. A repository cannot turn a wire
 * `feeling_key` into a domain [Feeling] without the catalog, so failing to load it is a failure of
 * the whole call rather than something to paper over with a half-populated entry.
 */
internal suspend fun <T> FeelingRepository.withCatalog(block: suspend (FeelingCatalog) -> ApiResult<T>): ApiResult<T> =
    when (val result = getCatalog()) {
        is ApiResult.Success -> block(result.data)
        is ApiResult.Error -> result
    }

private fun FeelingDto.toDomain(): Feeling =
    Feeling(
        key = key,
        label = label,
        valence = Valence.fromWire(valence),
    )
