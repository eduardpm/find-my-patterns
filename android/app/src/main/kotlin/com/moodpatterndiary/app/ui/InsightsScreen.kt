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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material.icons.filled.TrendingDown
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
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
import com.moodpatterndiary.app.data.InsightsRepository
import com.moodpatterndiary.app.data.NetworkModule
import com.moodpatterndiary.app.domain.Pattern
import com.moodpatterndiary.app.domain.PatternDirection
import kotlinx.coroutines.launch

data class InsightsUiState(
    val patterns: List<Pattern> = emptyList(),
    val insufficientData: Boolean = false,
    val isLoading: Boolean = true,
    val errorMessage: String? = null,
)

class InsightsViewModel(private val insightsRepository: InsightsRepository) : ViewModel() {
    var uiState by mutableStateOf(InsightsUiState())
        private set

    fun refresh() {
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null)
            when (val result = insightsRepository.getInsights()) {
                is ApiResult.Success ->
                    uiState =
                        uiState.copy(
                            isLoading = false,
                            patterns = result.data.patterns,
                            insufficientData = result.data.insufficientData,
                        )
                is ApiResult.Error -> uiState = uiState.copy(isLoading = false, errorMessage = result.message)
            }
        }
    }

    fun dismissError() {
        uiState = uiState.copy(errorMessage = null)
    }
}

/** Pattern cards + "need more data" empty state (US3, FR-010/FR-011/FR-012). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InsightsScreen() {
    val viewModel: InsightsViewModel =
        viewModel(
            factory =
                viewModelFactory {
                    initializer { InsightsViewModel(InsightsRepository(NetworkModule.insightsApi)) }
                },
        )
    val uiState = viewModel.uiState
    val snackbarHostState = remember { SnackbarHostState() }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer =
            LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_RESUME) viewModel.refresh()
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
        topBar = { TopAppBar(title = { Text("Insights") }) },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize()) {
            when {
                uiState.isLoading && uiState.patterns.isEmpty() ->
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                uiState.insufficientData || uiState.patterns.isEmpty() ->
                    InsufficientDataState(modifier = Modifier.align(Alignment.Center))
                else ->
                    LazyColumn(
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(uiState.patterns, key = { it.id }) { pattern -> PatternCard(pattern) }
                    }
            }
        }
    }
}

@Composable
private fun InsufficientDataState(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = Icons.Filled.Insights,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "Not enough data yet",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text =
                "Keep logging entries — once a topic and feeling repeat a few times, a " +
                    "pattern will show up here.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun PatternCard(pattern: Pattern) {
    val isChange = pattern.direction == PatternDirection.CHANGE
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = if (isChange) Icons.Filled.TrendingDown else Icons.Filled.TrendingUp,
                    contentDescription = null,
                    tint = if (isChange) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = pattern.topic.replaceFirstChar { it.uppercase() },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(text = pattern.narrativeText, style = MaterialTheme.typography.bodyLarge)
            Spacer(modifier = Modifier.height(8.dp))
            Surface(
                color = MaterialTheme.colorScheme.secondaryContainer,
                shape = MaterialTheme.shapes.medium,
            ) {
                Text(
                    text = pattern.suggestionText,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(12.dp),
                )
            }
        }
    }
}
