package com.moodpatterndiary.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
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
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.moodpatterndiary.app.data.ApiResult
import com.moodpatterndiary.app.data.EntryRepository
import com.moodpatterndiary.app.data.NetworkModule
import com.moodpatterndiary.app.domain.Entry
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

data class TodayUiState(
    val entries: List<Entry> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
)

class TodayViewModel(private val entryRepository: EntryRepository) : ViewModel() {
    var uiState by mutableStateOf(TodayUiState())
        private set

    fun refresh() {
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null)
            when (val result = entryRepository.listEntries(LocalDate.now())) {
                is ApiResult.Success -> uiState = uiState.copy(isLoading = false, entries = result.data)
                is ApiResult.Error -> uiState = uiState.copy(isLoading = false, errorMessage = result.message)
            }
        }
    }

    fun dismissError() {
        uiState = uiState.copy(errorMessage = null)
    }
}

/** The app's home screen (US1): today's entries plus a single prominent "new entry" FAB. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TodayScreen(
    onNewEntry: () -> Unit,
    onOpenEntry: (Entry) -> Unit,
) {
    val viewModel: TodayViewModel =
        viewModel(
            factory =
                viewModelFactory {
                    initializer { TodayViewModel(EntryRepository(NetworkModule.entryApi)) }
                },
        )
    val uiState = viewModel.uiState
    val snackbarHostState = remember { SnackbarHostState() }

    // Refresh on first show and every time this screen resumes (e.g. returning here after
    // saving a new entry) -- Navigation Compose's per-destination lifecycle moves through
    // ON_RESUME again on the way back, unlike a plain LaunchedEffect(Unit) which only runs once.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer =
            LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_RESUME) {
                    viewModel.refresh()
                }
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
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "Today",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                    )
                },
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = onNewEntry,
                icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                text = { Text("New entry") },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize()) {
            when {
                uiState.isLoading && uiState.entries.isEmpty() ->
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                uiState.entries.isEmpty() ->
                    EmptyTodayState(modifier = Modifier.align(Alignment.Center))
                else ->
                    LazyColumn(
                        contentPadding = PaddingValues(16.dp, 16.dp, 16.dp, 96.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(uiState.entries, key = { it.id }) { entry ->
                            EntryCard(entry = entry, onClick = { onOpenEntry(entry) })
                        }
                    }
            }
        }
    }
}

@Composable
private fun EmptyTodayState(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(text = "No entries yet today", style = MaterialTheme.typography.titleMedium)
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Tap “New entry” to write about what's going on.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun EntryCard(
    entry: Entry,
    onClick: () -> Unit,
) {
    ElevatedCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text =
                        DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
                            .format(entry.createdAt.atZone(ZoneId.systemDefault()).toLocalTime()),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                entry.feeling?.let { feeling ->
                    AssistChip(
                        onClick = {},
                        enabled = false,
                        label = { Text("${feeling.emoji} ${feeling.label}") },
                    )
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(text = entry.rawText, style = MaterialTheme.typography.bodyLarge, maxLines = 3)
        }
    }
}
