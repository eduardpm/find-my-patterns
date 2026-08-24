package com.moodpatterndiary.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.moodpatterndiary.app.data.ApiResult
import com.moodpatterndiary.app.data.EntryRepository
import com.moodpatterndiary.app.data.FeelingRepository
import com.moodpatterndiary.app.data.GuidingQuestionRepository
import com.moodpatterndiary.app.data.NetworkModule
import com.moodpatterndiary.app.domain.Entry
import com.moodpatterndiary.app.domain.Feeling
import com.moodpatterndiary.app.domain.GuidingQuestion
import com.moodpatterndiary.app.domain.GuidingQuestionAnswer
import com.moodpatterndiary.app.domain.defaultSelection
import com.moodpatterndiary.app.ui.components.FeelingChipRow
import kotlinx.coroutines.launch

/** Which step of the "new entry" flow is currently showing. */
sealed interface ComposerStage {
    data object Guided : ComposerStage

    data object Freeform : ComposerStage

    data class ConfirmFeeling(val entry: Entry) : ComposerStage
}

data class EntryComposerUiState(
    val stage: ComposerStage = ComposerStage.Guided,
    val guidingQuestions: List<GuidingQuestion> = emptyList(),
    val feelings: List<Feeling> = emptyList(),
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
)

class EntryComposerViewModel(
    private val entryRepository: EntryRepository,
    private val guidingQuestionRepository: GuidingQuestionRepository,
    private val feelingRepository: FeelingRepository,
) : ViewModel() {
    var uiState by mutableStateOf(EntryComposerUiState())
        private set

    init {
        viewModelScope.launch {
            when (val result = guidingQuestionRepository.getQuestions()) {
                is ApiResult.Success -> uiState = uiState.copy(guidingQuestions = result.data)
                is ApiResult.Error -> {
                    // Can't load the guided-question library (e.g. backend unreachable) --
                    // freeform writing (FR-005) still works without it.
                    uiState = uiState.copy(errorMessage = result.message, stage = ComposerStage.Freeform)
                }
            }
        }
        viewModelScope.launch {
            // The feeling set is backend-owned (T045). Loaded up front so the confirm step's chip
            // row is populated by the time an entry has been saved; a failure here is silent
            // because saving the entry is what matters and the same failure will surface there.
            val result = feelingRepository.getFeelings()
            if (result is ApiResult.Success) uiState = uiState.copy(feelings = result.data)
        }
    }

    fun switchToFreeform() {
        uiState = uiState.copy(stage = ComposerStage.Freeform)
    }

    fun switchToGuided() {
        uiState = uiState.copy(stage = ComposerStage.Guided)
    }

    fun saveGuided(answers: List<GuidingQuestionAnswer>) {
        if (answers.isEmpty()) return
        val combinedText = answers.joinToString(separator = "\n") { it.answerText }
        viewModelScope.launch {
            uiState = uiState.copy(isSaving = true, errorMessage = null)
            when (val result = entryRepository.createGuidedEntry(answers, combinedText)) {
                is ApiResult.Success ->
                    uiState = uiState.copy(isSaving = false, stage = ComposerStage.ConfirmFeeling(result.data))
                is ApiResult.Error -> uiState = uiState.copy(isSaving = false, errorMessage = result.message)
            }
        }
    }

    fun saveFreeform(text: String) {
        if (text.isBlank()) return
        viewModelScope.launch {
            uiState = uiState.copy(isSaving = true, errorMessage = null)
            when (val result = entryRepository.createFreeformEntry(text.trim())) {
                is ApiResult.Success ->
                    uiState = uiState.copy(isSaving = false, stage = ComposerStage.ConfirmFeeling(result.data))
                is ApiResult.Error -> uiState = uiState.copy(isSaving = false, errorMessage = result.message)
            }
        }
    }

    fun confirmFeeling(
        entryId: String,
        version: Int,
        feeling: Feeling,
        onSaved: () -> Unit,
    ) {
        viewModelScope.launch {
            uiState = uiState.copy(isSaving = true, errorMessage = null)
            when (val result = entryRepository.confirmFeeling(entryId, version, feeling)) {
                is ApiResult.Success -> {
                    uiState = uiState.copy(isSaving = false)
                    onSaved()
                }
                is ApiResult.Error -> uiState = uiState.copy(isSaving = false, errorMessage = result.message)
            }
        }
    }

    fun dismissError() {
        uiState = uiState.copy(errorMessage = null)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EntryComposer(
    onDone: () -> Unit,
    onCancel: () -> Unit,
) {
    val viewModel: EntryComposerViewModel =
        viewModel(
            factory =
                viewModelFactory {
                    initializer {
                        EntryComposerViewModel(
                            entryRepository = EntryRepository(NetworkModule.entryApi),
                            guidingQuestionRepository = GuidingQuestionRepository(NetworkModule.guidingQuestionApi),
                            feelingRepository = NetworkModule.feelingRepository,
                        )
                    }
                },
        )
    val uiState = viewModel.uiState
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(uiState.errorMessage) {
        uiState.errorMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.dismissError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("New entry") },
                navigationIcon = {
                    IconButton(onClick = onCancel) {
                        Icon(Icons.Filled.Close, contentDescription = "Cancel")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize()) {
            when (val stage = uiState.stage) {
                is ComposerStage.Guided ->
                    GuidedQuestionFlow(
                        library = uiState.guidingQuestions,
                        onBypassToFreeform = viewModel::switchToFreeform,
                        onComplete = viewModel::saveGuided,
                    )
                is ComposerStage.Freeform ->
                    FreeformEntryStep(
                        onBackToGuided = viewModel::switchToGuided,
                        onSave = viewModel::saveFreeform,
                        isSaving = uiState.isSaving,
                    )
                is ComposerStage.ConfirmFeeling ->
                    ConfirmFeelingStep(
                        entry = stage.entry,
                        feelings = uiState.feelings,
                        isSaving = uiState.isSaving,
                        onConfirm = { feeling ->
                            viewModel.confirmFeeling(
                                entryId = stage.entry.id,
                                version = stage.entry.version,
                                feeling = feeling,
                                onSaved = onDone,
                            )
                        },
                    )
            }

            if (uiState.isSaving && uiState.stage !is ComposerStage.ConfirmFeeling) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth().align(Alignment.TopCenter))
            }
        }
    }
}

@Composable
private fun FreeformEntryStep(
    onBackToGuided: () -> Unit,
    onSave: (String) -> Unit,
    isSaving: Boolean,
) {
    var text by rememberSaveable { mutableStateOf("") }

    Column(modifier = Modifier.fillMaxSize().padding(24.dp)) {
        Text(text = "What's going on?", style = MaterialTheme.typography.headlineSmall)
        Spacer(modifier = Modifier.height(20.dp))
        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            modifier = Modifier.fillMaxWidth().weight(1f),
            placeholder = { Text("Write whatever's on your mind…") },
        )
        Spacer(modifier = Modifier.height(16.dp))
        TextButton(onClick = onBackToGuided) {
            Text("Use guided questions instead")
        }
        Spacer(modifier = Modifier.height(8.dp))
        Button(
            onClick = { onSave(text) },
            enabled = text.isNotBlank() && !isSaving,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(if (isSaving) "Saving…" else "Save entry")
        }
    }
}

@Composable
private fun ConfirmFeelingStep(
    entry: Entry,
    feelings: List<Feeling>,
    isSaving: Boolean,
    onConfirm: (Feeling) -> Unit,
) {
    // Keyed on the fetched set too, so the default lands as soon as the set arrives rather than
    // staying null if the chip row was composed before `GET /feelings` came back.
    var selected: Feeling? by remember(entry.id, feelings) {
        mutableStateOf(entry.suggestedFeeling?.feeling ?: entry.feeling ?: feelings.defaultSelection())
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(32.dp))
        Text(text = "Entry saved.", style = MaterialTheme.typography.headlineSmall)
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text =
                if (entry.suggestedFeeling != null) {
                    "It sounds like you're feeling ${entry.suggestedFeeling.feeling.label.lowercase()}. " +
                        "Confirm it or pick a different feeling."
                } else {
                    "How would you describe how you felt?"
                },
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(24.dp))
        FeelingChipRow(feelings = feelings, selected = selected, onSelect = { selected = it })
        Spacer(modifier = Modifier.weight(1f))
        Button(
            onClick = { selected?.let(onConfirm) },
            enabled = !isSaving && selected != null,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(if (isSaving) "Saving…" else "Confirm")
        }
    }
}
