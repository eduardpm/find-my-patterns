package com.moodpatterndiary.app

import android.app.Application
import com.moodpatterndiary.app.data.NetworkModule
import com.moodpatterndiary.app.data.SettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * App entrypoint: keeps [NetworkModule]'s base URL in sync with whatever the user has entered on
 * [com.moodpatterndiary.app.ui.SettingsScreen] (research.md §6), for the whole process lifetime,
 * so every screen's Retrofit calls always target the current backend address without needing to
 * thread Settings state through every repository.
 */
class MoodPatternDiaryApp : Application() {
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    lateinit var settingsStore: SettingsStore
        private set

    override fun onCreate() {
        super.onCreate()

        settingsStore = SettingsStore(this)

        applicationScope.launch {
            settingsStore.backendAddress.collect { address ->
                NetworkModule.updateBaseUrl(address.host, address.port)
            }
        }
    }
}
