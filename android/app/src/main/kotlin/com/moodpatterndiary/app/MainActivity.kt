package com.moodpatterndiary.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import com.moodpatterndiary.app.notifications.ReminderNotifier
import com.moodpatterndiary.app.notifications.ReminderScheduler
import com.moodpatterndiary.app.ui.AppNavHost
import com.moodpatterndiary.app.ui.theme.MoodPatternDiaryTheme

/**
 * The app's single activity. Owns two Android-framework concerns that Compose can't:
 *  - Requesting the POST_NOTIFICATIONS runtime permission and (re-)arming the four daily
 *    reminder alarms on first launch (T060, FR-013).
 *  - Reading the "open composer" extra a reminder notification's PendingIntent sets
 *    (ReminderNotifier.EXTRA_OPEN_COMPOSER) so tapping a reminder deep-links straight into the
 *    entry composer (FR-014), both on cold start and via onNewIntent while already running
 *    (launchMode="singleTask" in the manifest).
 */
class MainActivity : ComponentActivity() {
    private var openComposerSignal by mutableIntStateOf(0)

    private val requestNotificationPermission =
        registerForActivityResult(
            ActivityResultContracts.RequestPermission(),
        ) { /* no-op: if denied, reminders still fire as alarms, just without a visible notification */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        requestNotificationPermissionIfNeeded()
        ReminderScheduler(applicationContext).scheduleAll()
        handleIntent(intent)

        setContent {
            MoodPatternDiaryTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    AppNavHost(openComposerSignal = openComposerSignal)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(ReminderNotifier.EXTRA_OPEN_COMPOSER, false) == true) {
            openComposerSignal += 1
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted =
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        if (!granted) {
            requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}
