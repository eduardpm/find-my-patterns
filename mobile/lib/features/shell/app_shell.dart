import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// The app shell: a bottom navigation bar over the four top-level tabs.
///
/// Each tab keeps its own navigation stack, so switching away and back returns
/// the user where they were.
///
/// The bar sits at the bottom while the web client's equivalent sits at the
/// top, because a thumb reaches the bottom of a phone and a pointer is already
/// at the top of a browser window. What the two share is the look: the same
/// paper surface, and the same hairline separating the nav from the content.
class AppShell extends StatelessWidget {
  /// Creates the shell around [navigationShell].
  const AppShell({super.key, required this.navigationShell});

  /// The branch-aware child supplied by `StatefulShellRoute`.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The hairline the web client draws under its nav, kept here between
          // the content and the bar so the bar reads as chrome rather than as
          // the last item in the list.
          Container(height: 1, color: context.journalColors.hairline),
          NavigationBar(
            backgroundColor: theme.colorScheme.surfaceContainer,
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => navigationShell.goBranch(
              index,
              // Tapping the current tab again returns it to its root.
              initialLocation: index == navigationShell.currentIndex,
            ),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.edit_note_outlined),
                selectedIcon: Icon(Icons.edit_note),
                label: 'Today',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Insights',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Calendar',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
