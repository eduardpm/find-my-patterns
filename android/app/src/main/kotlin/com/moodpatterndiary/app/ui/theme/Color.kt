package com.moodpatterndiary.app.ui.theme

import androidx.compose.ui.graphics.Color
import com.moodpatterndiary.app.domain.Feeling
import com.moodpatterndiary.app.domain.Valence

// Fallback (non-dynamic-color) Material 3 palette -- used on API < 31 or when the user's device
// doesn't support wallpaper-based dynamic color (research.md §5).
val Purple80 = Color(0xFFD0BCFF)
val PurpleGrey80 = Color(0xFFCCC2DC)
val Pink80 = Color(0xFFEFB8C8)

val JournalPrimary = Color(0xFF6750A4)
val JournalSecondary = Color(0xFF625B71)
val JournalTertiary = Color(0xFF7D5260)

// Per-feeling accent colors. Like emoji, these are presentation and stay client-side -- the
// backend owns which feelings exist and what they mean, not what they look like.
private val feelingDotColors =
    mapOf(
        "happy" to Color(0xFF4CAF50),
        "excited" to Color(0xFFFFC107),
        "neutral" to Color(0xFF9E9E9E),
        "sleepy" to Color(0xFF64B5F6),
        "exhausted" to Color(0xFF7986CB),
        "stressed" to Color(0xFFFF7043),
        "sad" to Color(0xFF5C6BC0),
        "depressed" to Color(0xFF616161),
    )

/**
 * A small accent color per feeling, used as calendar-day dots (FR-015) and chip accents.
 *
 * A feeling the backend gained after this build shipped has no color of its own, so it falls back
 * to a generic one picked from the valence the backend told us about -- still readable, and the
 * app doesn't need a release to cope with a new feeling.
 */
fun Feeling.dotColor(): Color =
    feelingDotColors[key] ?: when (valence) {
        Valence.POSITIVE -> Color(0xFF66BB6A)
        Valence.NEGATIVE -> Color(0xFF7986CB)
        else -> Color(0xFF9E9E9E)
    }
