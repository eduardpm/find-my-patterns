package com.moodpatterndiary.app.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

private val Context.settingsDataStore by preferencesDataStore(name = "settings")

/** The user-entered backend address (research.md §6): a host/IP plus a port, typed once in Settings. */
data class BackendAddress(val host: String, val port: Int) {
    val isConfigured: Boolean get() = host.isNotBlank()

    companion object {
        const val DEFAULT_PORT = 8000
        val UNSET = BackendAddress(host = "", port = DEFAULT_PORT)
    }
}

/**
 * Persists the backend host/port locally (DataStore Preferences) so [SettingsScreen] and
 * [NetworkModule] agree on where the backend lives without needing any network discovery
 * (research.md §6: manual pairing is the deliberate v1 choice).
 */
class SettingsStore(context: Context) {
    private val appContext = context.applicationContext

    private object Keys {
        val HOST = stringPreferencesKey("backend_host")
        val PORT = intPreferencesKey("backend_port")
    }

    val backendAddress: Flow<BackendAddress> =
        appContext.settingsDataStore.data
            .map { prefs ->
                BackendAddress(
                    host = prefs[Keys.HOST] ?: "",
                    port = prefs[Keys.PORT] ?: BackendAddress.DEFAULT_PORT,
                )
            }
            .distinctUntilChanged()

    suspend fun saveBackendAddress(
        host: String,
        port: Int,
    ) {
        appContext.settingsDataStore.edit { prefs ->
            prefs[Keys.HOST] = host.trim()
            prefs[Keys.PORT] = port
        }
    }
}
