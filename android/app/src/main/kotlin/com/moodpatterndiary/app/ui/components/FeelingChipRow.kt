package com.moodpatterndiary.app.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.moodpatterndiary.app.domain.Feeling

/**
 * Horizontally scrollable row of the feeling set, with [selected] highlighted -- the
 * confirm/override control for FR-007's hybrid suggest-then-confirm feeling flow, reused by both
 * the entry composer's confirmation step and the entry detail/edit screen.
 *
 * [feelings] is the backend-served set (`GET /feelings`, T044/T045), passed in by the calling
 * screen's ViewModel rather than read from a hardcoded enum -- constitution Principle VII. It is
 * empty while that fetch is in flight, in which case the row simply renders nothing. [selected]
 * is nullable for the same reason: before the set arrives there is nothing that could be selected.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeelingChipRow(
    feelings: List<Feeling>,
    selected: Feeling?,
    onSelect: (Feeling) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(horizontal = 4.dp),
    ) {
        items(feelings, key = { it.key }) { feeling ->
            FilterChip(
                selected = feeling.key == selected?.key,
                onClick = { onSelect(feeling) },
                label = { Text("${feeling.emoji} ${feeling.label}") },
            )
        }
    }
}
