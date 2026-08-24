package com.moodpatterndiary.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.moodpatterndiary.app.data.BackendAddress
import com.moodpatterndiary.app.data.SettingsStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

data class SettingsUiState(
    val host: String = "",
    val port: String = BackendAddress.DEFAULT_PORT.toString(),
    val isLoading: Boolean = true,
    val savedMessage: String? = null,
)

class SettingsViewModel(private val settingsStore: SettingsStore) : ViewModel() {
    var uiState by mutableStateOf(SettingsUiState())
        private set

    init {
        viewModelScope.launch {
            val current = settingsStore.backendAddress.first()
            uiState = uiState.copy(host = current.host, port = current.port.toString(), isLoading = false)
        }
    }

    fun updateHost(value: String) {
        uiState = uiState.copy(host = value, savedMessage = null)
    }

    fun updatePort(value: String) {
        uiState = uiState.copy(port = value.filter { it.isDigit() }, savedMessage = null)
    }

    fun save() {
        val host = uiState.host.trim()
        val port = uiState.port.toIntOrNull() ?: BackendAddress.DEFAULT_PORT
        viewModelScope.launch {
            settingsStore.saveBackendAddress(host, port)
            uiState =
                uiState.copy(
                    host = host,
                    port = port.toString(),
                    savedMessage = "Saved. The app will now use $host:$port.",
                )
        }
    }
}

/** Backend host/IP + port pairing (research.md §6), persisted locally via [SettingsStore]. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val viewModel: SettingsViewModel =
        viewModel(
            factory =
                viewModelFactory {
                    initializer { SettingsViewModel(SettingsStore(context.applicationContext)) }
                },
        )
    val uiState = viewModel.uiState

    Scaffold(
        topBar = { TopAppBar(title = { Text("Settings") }) },
    ) { padding ->
        Column(modifier = Modifier.padding(padding).padding(24.dp).fillMaxSize()) {
            Text(text = "Backend connection", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text =
                    "Enter the local IP address and port of the diary backend running on your " +
                        "home machine, as printed when you start the server (e.g. 192.168.1.42:8000). " +
                        "The app only works while your phone can reach that address directly.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(24.dp))

            if (uiState.isLoading) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            } else {
                OutlinedTextField(
                    value = uiState.host,
                    onValueChange = viewModel::updateHost,
                    label = { Text("Host or IP address") },
                    placeholder = { Text("192.168.1.42") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(modifier = Modifier.height(16.dp))
                OutlinedTextField(
                    value = uiState.port,
                    onValueChange = viewModel::updatePort,
                    label = { Text("Port") },
                    placeholder = { Text(BackendAddress.DEFAULT_PORT.toString()) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(modifier = Modifier.height(24.dp))
                Button(
                    onClick = viewModel::save,
                    enabled = uiState.host.isNotBlank(),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Save")
                }
                uiState.savedMessage?.let { message ->
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(text = message, color = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}
