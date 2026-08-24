package com.moodpatterndiary.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.moodpatterndiary.app.data.ApiResult
import com.moodpatterndiary.app.data.EntryRepository
import com.moodpatterndiary.app.data.FeelingRepository
import com.moodpatterndiary.app.data.NetworkModule
import com.moodpatterndiary.app.domain.Entry
import com.moodpatterndiary.app.domain.Feeling
import com.moodpatterndiary.app.domain.defaultSelection
import com.moodpatterndiary.app.ui.components.FeelingChipRow
import kotlinx.coroutines.launch
import java.time.LocalDate

data class EntryDetailUiState(
    val entry: Entry? = null,
    val editedText: String = "",
    val editedFeeling: Feeling? = null,
    /** The backend-served feeling set (T045); empty until `GET /feelings` returns. */
    val feelings: List<Feeling> = emptyList(),
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
    val deleted: Boolean = false,
    /**
     * Set when a save or delete was refused because this screen's copy was out of date (FR-011).
     * Holds both sides so the user can compare and choose — never resolved automatically (FR-023).
     */
    val conflict: EntryConflict? = null,
)

/**
 * A rejected mutation, kept until the user decides what to do with it.
 *
 * [mine] is what they had written and tried to save. It is retained deliberately: losing what
 * someone just typed into a diary is the worst failure this app can have, so the text survives the
 * rejection and only ever leaves the screen because the user said so (FR-023).
 */
data class EntryConflict(
    val mine: String,
    val myFeeling: Feeling?,
    val current: Entry,
)

/**
 * There's no `GET /entries/{id}` in contracts/api.md (only `GET /entries?date=`), so this loads
 * the day's entries and picks the matching one out of that list -- also guarantees the detail
 * screen always reflects the latest server state rather than a possibly-stale object passed
 * through navigation.
 */
class EntryDetailViewModel(
    private val entryRepository: EntryRepository,
    private val feelingRepository: FeelingRepository,
    private val entryId: String,
    private val entryDate: LocalDate,
) : ViewModel() {
    var uiState by mutableStateOf(EntryDetailUiState())
        private set

    init {
        load()
        viewModelScope.launch {
            val result = feelingRepository.getFeelings()
            if (result is ApiResult.Success) uiState = uiState.copy(feelings = result.data)
        }
    }

    fun load() {
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null)
            when (val result = entryRepository.listEntries(entryDate)) {
                is ApiResult.Success -> {
                    val entry = result.data.firstOrNull { it.id == entryId }
                    uiState =
                        uiState.copy(
                            isLoading = false,
                            entry = entry,
                            editedText = entry?.rawText.orEmpty(),
                            editedFeeling = entry?.feeling,
                            errorMessage = if (entry == null) "This entry could no longer be found." else null,
                        )
                }
                is ApiResult.Error -> uiState = uiState.copy(isLoading = false, errorMessage = result.message)
            }
        }
    }

    fun updateText(text: String) {
        uiState = uiState.copy(editedText = text)
    }

    fun updateFeeling(feeling: Feeling) {
        uiState = uiState.copy(editedFeeling = feeling)
    }

    fun save(version: Int? = null) {
        val entry = uiState.entry ?: return
        viewModelScope.launch {
            uiState = uiState.copy(isSaving = true, errorMessage = null)
            val result =
                entryRepository.updateEntry(
                    entryId = entry.id,
                    // The version this screen loaded (FR-022), or the one carried out of a
                    // conflict when the user chose to retry. If another client has moved the entry
                    // on since then, the save comes back as ApiResult.StaleEntry.
                    version = version ?: entry.version,
                    text = uiState.editedText.trim(),
                    feeling = uiState.editedFeeling,
                )
            uiState =
                when (result) {
                    is ApiResult.Success -> uiState.copy(isSaving = false, entry = result.data, conflict = null)
                    // Must precede `is ApiResult.Error` — StaleEntry is a subtype of it, and the
                    // first matching branch of a `when` wins.
                    is ApiResult.StaleEntry ->
                        uiState.copy(
                            isSaving = false,
                            conflict =
                                EntryConflict(
                                    mine = uiState.editedText,
                                    myFeeling = uiState.editedFeeling,
                                    current = result.current,
                                ),
                        )
                    is ApiResult.Error -> uiState.copy(isSaving = false, errorMessage = result.message)
                }
        }
    }

    fun delete() {
        val entry = uiState.entry ?: return
        viewModelScope.launch {
            uiState = uiState.copy(isSaving = true, errorMessage = null)
            uiState =
                when (val result = entryRepository.deleteEntry(entry.id, entry.version)) {
                    is ApiResult.Success -> uiState.copy(isSaving = false, deleted = true)
                    // FR-021: a stale delete is refused. Show what the entry looks like now so the
                    // user can decide again with current information rather than destroying a
                    // change they never saw.
                    is ApiResult.StaleEntry ->
                        uiState.copy(
                            isSaving = false,
                            conflict =
                                EntryConflict(
                                    mine = uiState.editedText,
                                    myFeeling = uiState.editedFeeling,
                                    current = result.current,
                                ),
                        )
                    is ApiResult.Error -> uiState.copy(isSaving = false, errorMessage = result.message)
                }
        }
    }

    /** "Keep mine": retry against the version the conflict reported, which is current by definition. */
    fun retryWithCurrentVersion() {
        val conflict = uiState.conflict ?: return
        uiState = uiState.copy(conflict = null)
        save(version = conflict.current.version)
    }

    /** "Discard mine": adopt what the server has and drop the local edit — only on request. */
    fun discardMine() {
        val conflict = uiState.conflict ?: return
        uiState =
            uiState.copy(
                conflict = null,
                entry = conflict.current,
                editedText = conflict.current.rawText,
                editedFeeling = conflict.current.feeling,
            )
    }

    /**
     * "Keep editing": put their words back in the editor against the now-current entry so they can
     * merge by hand. The two versions are never combined automatically — that would produce text
     * the user never wrote.
     */
    fun carryMineAcross() {
        val conflict = uiState.conflict ?: return
        uiState =
            uiState.copy(
                conflict = null,
                entry = conflict.current,
                editedText = conflict.mine,
                editedFeeling = conflict.myFeeling,
            )
    }

    fun dismissError() {
        uiState = uiState.copy(errorMessage = null)
    }
}

/** View/edit/delete a single entry (FR-008). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EntryDetailScreen(
    entryId: String,
    entryDate: String,
    onDeleted: () -> Unit,
    onClose: () -> Unit,
) {
    val viewModel: EntryDetailViewModel =
        viewModel(
            factory =
                viewModelFactory {
                    initializer {
                        EntryDetailViewModel(
                            entryRepository = EntryRepository(NetworkModule.entryApi),
                            feelingRepository = NetworkModule.feelingRepository,
                            entryId = entryId,
                            entryDate = LocalDate.parse(entryDate),
                        )
                    }
                },
        )
    val uiState = viewModel.uiState
    val snackbarHostState = remember { SnackbarHostState() }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(uiState.deleted) {
        if (uiState.deleted) onDeleted()
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
                title = { Text("Entry") },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { showDeleteConfirm = true }, enabled = uiState.entry != null) {
                        Icon(Icons.Filled.Delete, contentDescription = "Delete entry")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize()) {
            when {
                // Before everything else: a refused change means the user has a decision to make,
                // and their words are being held until they make it (FR-023).
                uiState.conflict != null ->
                    ConflictPanel(
                        conflict = uiState.conflict,
                        onKeepMine = viewModel::retryWithCurrentVersion,
                        onDiscardMine = viewModel::discardMine,
                        onKeepEditing = viewModel::carryMineAcross,
                        modifier = Modifier.fillMaxSize().padding(24.dp),
                    )
                uiState.isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                uiState.entry == null ->
                    Text(
                        text = "This entry is no longer available.",
                        modifier = Modifier.align(Alignment.Center).padding(24.dp),
                    )
                else ->
                    Column(modifier = Modifier.fillMaxSize().padding(24.dp)) {
                        OutlinedTextField(
                            value = uiState.editedText,
                            onValueChange = viewModel::updateText,
                            modifier = Modifier.fillMaxWidth().weight(1f),
                            label = { Text("Entry text") },
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(text = "Feeling", style = MaterialTheme.typography.titleMedium)
                        Spacer(modifier = Modifier.height(8.dp))
                        FeelingChipRow(
                            feelings = uiState.feelings,
                            selected = uiState.editedFeeling ?: uiState.feelings.defaultSelection(),
                            onSelect = viewModel::updateFeeling,
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Button(
                            onClick = viewModel::save,
                            enabled = !uiState.isSaving && uiState.editedText.isNotBlank(),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(if (uiState.isSaving) "Saving…" else "Save changes")
                        }
                    }
            }

            if (showDeleteConfirm) {
                AlertDialog(
                    onDismissRequest = { showDeleteConfirm = false },
                    title = { Text("Delete this entry?") },
                    text = { Text("This can't be undone.") },
                    confirmButton = {
                        TextButton(onClick = {
                            showDeleteConfirm = false
                            viewModel.delete()
                        }) { Text("Delete") }
                    },
                    dismissButton = {
                        TextButton(onClick = { showDeleteConfirm = false }) { Text("Cancel") }
                    },
                )
            }
        }
    }
}

/**
 * Shown when a save or delete was refused because this screen's copy was out of date (FR-023).
 *
 * The design rule is "reject and preserve", identical to the web client's conflict screen: the
 * user's text stays on screen beside what's actually stored, and they choose. There is deliberately
 * no merge option — combining the two would produce text they never wrote, which in a diary is
 * worse than either version winning.
 */
@Composable
private fun ConflictPanel(
    conflict: EntryConflict,
    onKeepMine: () -> Unit,
    onDiscardMine: () -> Unit,
    onKeepEditing: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.verticalScroll(rememberScrollState())) {
        Text(text = "This entry changed elsewhere", style = MaterialTheme.typography.titleLarge)
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text =
                "You edited this on another device since this screen loaded, so nothing was " +
                    "overwritten. Here's what you wrote and what's saved now.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(24.dp))
        Text(text = "What you wrote", style = MaterialTheme.typography.titleMedium)
        Spacer(modifier = Modifier.height(8.dp))
        Card(modifier = Modifier.fillMaxWidth()) {
            Text(text = conflict.mine, modifier = Modifier.padding(16.dp))
        }

        Spacer(modifier = Modifier.height(24.dp))
        Text(text = "What's saved now", style = MaterialTheme.typography.titleMedium)
        Spacer(modifier = Modifier.height(8.dp))
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        ) {
            Text(text = conflict.current.rawText, modifier = Modifier.padding(16.dp))
        }

        Spacer(modifier = Modifier.height(24.dp))
        Button(onClick = onKeepMine, modifier = Modifier.fillMaxWidth()) {
            Text("Keep mine (overwrite)")
        }
        Spacer(modifier = Modifier.height(8.dp))
        OutlinedButton(onClick = onKeepEditing, modifier = Modifier.fillMaxWidth()) {
            Text("Keep editing mine")
        }
        Spacer(modifier = Modifier.height(8.dp))
        TextButton(onClick = onDiscardMine, modifier = Modifier.fillMaxWidth()) {
            Text("Discard mine and use theirs")
        }
    }
}
