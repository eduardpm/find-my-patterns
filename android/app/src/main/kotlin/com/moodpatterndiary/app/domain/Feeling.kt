package com.moodpatterndiary.app.domain

/**
 * How a feeling is scored, which is what makes insights point at "keep doing this" versus
 * "consider changing this". Because that is a *rule* and not presentation, which feeling carries
 * which valence is decided by the backend and served by `GET /feelings` (003 contracts/api.md) --
 * this enum only names the closed vocabulary the contract defines, with [UNKNOWN] so a value the
 * backend adds later can't crash the client.
 */
enum class Valence {
    POSITIVE,
    NEUTRAL,
    NEGATIVE,
    UNKNOWN,
    ;

    companion object {
        fun fromWire(raw: String): Valence =
            when (raw.lowercase()) {
                "positive" -> POSITIVE
                "neutral" -> NEUTRAL
                "negative" -> NEGATIVE
                else -> UNKNOWN
            }
    }
}

/**
 * One feeling from the predefined mood set (data-model.md `Feeling`).
 *
 * This used to be a hardcoded `enum class` that duplicated the backend's seeded `feelings` table.
 * Constitution Principle VII (single source of truth for rules) forbids that: the set's membership,
 * labels and -- most importantly -- valences are now fetched from `GET /feelings` and carried in
 * this value type. Build instances only from a [FeelingCatalog]; never invent one locally.
 *
 * [emoji] is the deliberate exception. It is presentation, the backend does not serve it
 * (contracts/api.md: "Emoji are deliberately not included"), so it stays client-side in
 * [FeelingEmoji] and is keyed off [key] with a safe fallback.
 */
data class Feeling(
    val key: String,
    val label: String,
    val valence: Valence,
) {
    val emoji: String get() = FeelingEmoji.forKey(key)
}

/**
 * Client-side emoji for each feeling key. Purely presentational (see [Feeling.emoji]); an unknown
 * key -- a feeling the backend gained after this build shipped -- falls back rather than failing,
 * so the feeling set stays backend-owned.
 */
object FeelingEmoji {
    const val FALLBACK: String = "🙂"

    private val byKey =
        mapOf(
            "happy" to "😊",
            "excited" to "🤩",
            "neutral" to "😐",
            "sleepy" to "😴",
            "exhausted" to "🥱",
            "stressed" to "😖",
            "sad" to "😢",
            "depressed" to "😞",
        )

    fun forKey(key: String): String = byKey[key] ?: FALLBACK
}

/**
 * An immutable snapshot of the backend-served feeling set, in the backend's own order (which
 * contracts/api.md guarantees is stable). Replaces the old `Feeling.all` / `Feeling.fromKey`
 * companion helpers: resolving a wire `feeling_key` now requires a catalog, which is exactly the
 * compile-time pressure that keeps the set from being re-hardcoded.
 */
data class FeelingCatalog(val feelings: List<Feeling>) {
    private val byKey: Map<String, Feeling> = feelings.associateBy { it.key }

    fun fromKey(key: String?): Feeling? = key?.let { byKey[it] }

    companion object {
        val EMPTY = FeelingCatalog(emptyList())
    }
}

/**
 * The chip-row's default highlight when the user hasn't picked anything yet. Chosen by valence
 * rather than by a hardcoded "neutral" key so the backend still owns the set (Principle VII).
 */
fun List<Feeling>.defaultSelection(): Feeling? = firstOrNull { it.valence == Valence.NEUTRAL } ?: firstOrNull()
