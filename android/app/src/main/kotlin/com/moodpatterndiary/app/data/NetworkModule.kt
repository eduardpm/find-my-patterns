package com.moodpatterndiary.app.data

import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import com.moodpatterndiary.app.BuildConfig
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import java.io.IOException
import java.util.concurrent.TimeUnit

/** Thrown by [NetworkModule]'s interceptor when no backend host has been configured yet. */
class BackendNotConfiguredException : IOException("Backend address not configured")

/**
 * Builds the shared Retrofit/OkHttp client (research.md §6, T014).
 *
 * The backend address is entered by the user on [com.moodpatterndiary.app.ui.SettingsScreen]
 * and can change at any time, but Retrofit itself needs a fixed base URL at construction time.
 * Rather than tearing down and rebuilding Retrofit whenever Settings changes, a single
 * placeholder base URL is used and a request interceptor rewrites the scheme/host/port of every
 * outgoing request to the current, in-memory backend address — kept up to date by
 * [com.moodpatterndiary.app.MoodPatternDiaryApp] collecting [SettingsStore.backendAddress].
 */
object NetworkModule {
    private val placeholderBaseUrl: HttpUrl = "http://backend.not.configured/".toHttpUrl()

    @Volatile
    private var currentBaseUrl: HttpUrl? = null

    fun updateBaseUrl(
        host: String,
        port: Int,
    ) {
        currentBaseUrl =
            if (host.isBlank()) {
                null
            } else {
                HttpUrl.Builder()
                    .scheme("http")
                    .host(host)
                    .port(port)
                    .build()
            }
    }

    private val dynamicBaseUrlInterceptor =
        Interceptor { chain ->
            val target = currentBaseUrl ?: throw BackendNotConfiguredException()
            val original = chain.request()
            val redirected =
                original.url.newBuilder()
                    .scheme(target.scheme)
                    .host(target.host)
                    .port(target.port)
                    .build()
            chain.proceed(original.newBuilder().url(redirected).build())
        }

    private val loggingInterceptor =
        HttpLoggingInterceptor().apply {
            level = if (BuildConfig.DEBUG) HttpLoggingInterceptor.Level.BASIC else HttpLoggingInterceptor.Level.NONE
        }

    private val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .addInterceptor(dynamicBaseUrlInterceptor)
            .addInterceptor(loggingInterceptor)
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(10, TimeUnit.SECONDS)
            .build()
    }

    val json: Json =
        Json {
            ignoreUnknownKeys = true
            explicitNulls = false
            encodeDefaults = true
        }

    private val retrofit: Retrofit by lazy {
        Retrofit.Builder()
            .baseUrl(placeholderBaseUrl)
            .client(okHttpClient)
            .addConverterFactory(
                json.asConverterFactory("application/json".toMediaType()),
            )
            .build()
    }

    val entryApi: EntryApi by lazy { retrofit.create(EntryApi::class.java) }
    val feelingApi: FeelingApi by lazy { retrofit.create(FeelingApi::class.java) }
    val guidingQuestionApi: GuidingQuestionApi by lazy { retrofit.create(GuidingQuestionApi::class.java) }
    val insightsApi: InsightsApi by lazy { retrofit.create(InsightsApi::class.java) }
    val monthlySummaryApi: MonthlySummaryApi by lazy { retrofit.create(MonthlySummaryApi::class.java) }

    /**
     * Shared, process-wide cache of the backend-served feeling set. Unlike the other repositories
     * this one is a singleton rather than constructed per screen: the set is fixed, several
     * repositories and screens need it, and caching it once means the extra `GET /feelings` costs
     * a single request per app launch.
     */
    val feelingRepository: FeelingRepository by lazy { FeelingRepository(feelingApi) }
}
