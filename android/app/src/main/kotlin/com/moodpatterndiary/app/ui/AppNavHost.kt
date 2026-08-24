package com.moodpatterndiary.app.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.moodpatterndiary.app.domain.Entry

/** All navigation destinations in the app. */
object Routes {
    const val TODAY = "today"
    const val COMPOSER = "composer"
    const val ENTRY_DETAIL = "entry/{entryId}/{entryDate}"
    const val INSIGHTS = "insights"
    const val CALENDAR = "calendar"
    const val SETTINGS = "settings"

    fun entryDetail(entry: Entry): String = "entry/${entry.id}/${entry.entryDate}"
}

private data class TopLevelDestination(val route: String, val label: String, val icon: ImageVector)

private val topLevelDestinations =
    listOf(
        TopLevelDestination(Routes.TODAY, "Today", Icons.Filled.EditNote),
        TopLevelDestination(Routes.INSIGHTS, "Insights", Icons.Filled.Insights),
        TopLevelDestination(Routes.CALENDAR, "Calendar", Icons.Filled.CalendarMonth),
        TopLevelDestination(Routes.SETTINGS, "Settings", Icons.Filled.Settings),
    )

/**
 * The app's single nav graph, plus a bottom bar over the 4 top-level destinations (research.md
 * §5's "modern app shell" bar). [openComposerSignal] is bumped by MainActivity every time the app
 * is opened/resumed from a reminder-notification tap (FR-014) -- incrementing rather than a plain
 * boolean lets the same "open composer" request re-fire even if the app was already showing the
 * composer from a previous tap.
 */
@Composable
fun AppNavHost(openComposerSignal: Int) {
    val navController = rememberNavController()

    LaunchedEffect(openComposerSignal) {
        if (openComposerSignal > 0) {
            navController.navigate(Routes.COMPOSER) { launchSingleTop = true }
        }
    }

    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = backStackEntry?.destination

    Scaffold(
        bottomBar = {
            val showBottomBar = topLevelDestinations.any { it.route == currentDestination?.route }
            if (showBottomBar) {
                NavigationBar {
                    topLevelDestinations.forEach { destination ->
                        NavigationBarItem(
                            selected = currentDestination?.hierarchy?.any { it.route == destination.route } == true,
                            onClick = {
                                navController.navigate(destination.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(destination.icon, contentDescription = destination.label) },
                            label = { Text(destination.label) },
                        )
                    }
                }
            }
        },
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Routes.TODAY,
            modifier = Modifier.padding(innerPadding),
        ) {
            composable(Routes.TODAY) {
                TodayScreen(
                    onNewEntry = { navController.navigate(Routes.COMPOSER) },
                    onOpenEntry = { entry -> navController.navigate(Routes.entryDetail(entry)) },
                )
            }
            composable(Routes.COMPOSER) {
                EntryComposer(
                    onDone = { navController.popBackStack(Routes.TODAY, inclusive = false) },
                    onCancel = { navController.popBackStack() },
                )
            }
            composable(
                route = Routes.ENTRY_DETAIL,
                arguments =
                    listOf(
                        navArgument("entryId") { type = NavType.StringType },
                        navArgument("entryDate") { type = NavType.StringType },
                    ),
            ) { entry ->
                val entryId = entry.arguments?.getString("entryId").orEmpty()
                val entryDate = entry.arguments?.getString("entryDate").orEmpty()
                EntryDetailScreen(
                    entryId = entryId,
                    entryDate = entryDate,
                    onDeleted = { navController.popBackStack() },
                    onClose = { navController.popBackStack() },
                )
            }
            composable(Routes.INSIGHTS) { InsightsScreen() }
            composable(Routes.CALENDAR) { MonthlyCalendarScreen() }
            composable(Routes.SETTINGS) { SettingsScreen() }
        }
    }
}
