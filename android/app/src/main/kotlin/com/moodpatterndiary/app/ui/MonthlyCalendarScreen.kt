package com.moodpatterndiary.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.moodpatterndiary.app.data.ApiResult
import com.moodpatterndiary.app.data.MonthlySummaryRepository
import com.moodpatterndiary.app.data.NetworkModule
import com.moodpatterndiary.app.domain.DaySummary
import com.moodpatterndiary.app.domain.Feeling
import com.moodpatterndiary.app.domain.MonthlySummary
import com.moodpatterndiary.app.ui.theme.dotColor
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.TextStyle
import java.util.Locale

data class MonthlyCalendarUiState(
    val month: YearMonth = YearMonth.now(),
    val summary: MonthlySummary? = null,
    val isLoading: Boolean = true,
    val errorMessage: String? = null,
)

class MonthlyCalendarViewModel(private val repository: MonthlySummaryRepository) : ViewModel() {
    var uiState by mutableStateOf(MonthlyCalendarUiState())
        private set

    fun load(month: YearMonth) {
        viewModelScope.launch {
            uiState = uiState.copy(month = month, isLoading = true, errorMessage = null)
            when (val result = repository.getSummary(month)) {
                is ApiResult.Success -> uiState = uiState.copy(isLoading = false, summary = result.data)
                is ApiResult.Error -> uiState = uiState.copy(isLoading = false, errorMessage = result.message)
            }
        }
    }

    fun previousMonth() = load(uiState.month.minusMonths(1))

    fun nextMonth() = load(uiState.month.plusMonths(1))

    fun dismissError() {
        uiState = uiState.copy(errorMessage = null)
    }
}

/** Monthly calendar grid + per-feeling totals/average panel (US5, FR-015/FR-016). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MonthlyCalendarScreen() {
    val viewModel: MonthlyCalendarViewModel =
        viewModel(
            factory =
                viewModelFactory {
                    initializer { MonthlyCalendarViewModel(MonthlySummaryRepository(NetworkModule.monthlySummaryApi)) }
                },
        )
    val uiState = viewModel.uiState
    val snackbarHostState = remember { SnackbarHostState() }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        // Reads viewModel.uiState.month live (not the `uiState` val above) since this observer
        // lambda is only created once and must always reload whichever month is current at the
        // moment it actually resumes, not whichever month was showing at first composition.
        val observer =
            LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_RESUME) viewModel.load(viewModel.uiState.month)
            }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(uiState.errorMessage) {
        uiState.errorMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.dismissError()
        }
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Monthly overview") }) },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier =
                Modifier
                    .padding(padding)
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState()),
        ) {
            MonthSwitcher(month = uiState.month, onPrevious = viewModel::previousMonth, onNext = viewModel::nextMonth)

            Box(modifier = Modifier.fillMaxWidth()) {
                if (uiState.isLoading && uiState.summary == null) {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.Center).padding(32.dp))
                } else {
                    uiState.summary?.let { summary ->
                        Column {
                            CalendarGrid(month = uiState.month, days = summary.days)
                            Spacer(modifier = Modifier.height(16.dp))
                            TotalsPanel(summary)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MonthSwitcher(
    month: YearMonth,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onPrevious) {
            Icon(Icons.Filled.ChevronLeft, contentDescription = "Previous month")
        }
        Text(
            text = "${month.month.getDisplayName(TextStyle.FULL, Locale.getDefault())} ${month.year}",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
        )
        IconButton(onClick = onNext) {
            Icon(Icons.Filled.ChevronRight, contentDescription = "Next month")
        }
    }
}

@Composable
private fun CalendarGrid(
    month: YearMonth,
    days: List<DaySummary>,
) {
    val daysByDate = remember(days) { days.associateBy { it.date } }
    val firstOfMonth = month.atDay(1)
    val daysInMonth = month.lengthOfMonth()
    // Monday-first grid: number of leading blank cells before day 1.
    val leadingBlanks = (firstOfMonth.dayOfWeek.value - DayOfWeek.MONDAY.value + 7) % 7
    val rowCount = (daysInMonth + leadingBlanks + 6) / 7

    Column(modifier = Modifier.padding(horizontal = 16.dp)) {
        Row(modifier = Modifier.fillMaxWidth()) {
            listOf("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su").forEach { label ->
                Text(
                    text = label,
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        LazyVerticalGrid(
            columns = GridCells.Fixed(7),
            modifier = Modifier.height((rowCount * 48).dp),
            userScrollEnabled = false,
        ) {
            items(leadingBlanks) { Box(modifier = Modifier.size(48.dp)) }
            items(daysInMonth) { index ->
                val date = firstOfMonth.plusDays(index.toLong())
                val feelings = daysByDate[date]?.feelings.orEmpty()
                DayCell(date = date, feelings = feelings)
            }
        }
    }
}

@Composable
private fun DayCell(
    date: LocalDate,
    feelings: List<Feeling>,
) {
    Box(
        modifier = Modifier.size(48.dp).padding(4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(text = date.dayOfMonth.toString(), style = MaterialTheme.typography.bodyMedium)
            if (feelings.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    feelings.take(3).forEach { feeling ->
                        Box(
                            modifier =
                                Modifier
                                    .size(6.dp)
                                    .clip(CircleShape)
                                    .background(feeling.dotColor()),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TotalsPanel(summary: MonthlySummary) {
    Column(modifier = Modifier.padding(16.dp)) {
        Text(text = "This month", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "Average ${String.format(Locale.getDefault(), "%.1f", summary.averageEntriesPerDay)} entries / day",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(12.dp))
        // Already in the backend's own feeling order -- MonthlySummaryRepository builds this map by
        // walking the served feeling set, so the panel doesn't need its own copy of that order.
        summary.totalsByFeeling.forEach { (feeling, count) ->
            if (count > 0) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(text = "${feeling.emoji} ${feeling.label}")
                    Text(text = count.toString(), fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}
