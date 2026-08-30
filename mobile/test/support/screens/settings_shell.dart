import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/features/settings/digest_card.dart';
import 'package:find_my_patterns/features/settings/export/export_controller.dart';
import 'package:find_my_patterns/features/settings/export/export_row.dart';
import 'package:find_my_patterns/features/settings/export/export_state.dart';
import 'package:find_my_patterns/features/settings/reminders_card.dart';
import 'package:find_my_patterns/features/settings/settings_screen.dart';
import 'package:find_my_patterns/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../harness.dart';
import '../screen_registry.dart';

/// A configured backend, several reminders at realistic times (mixed on and
/// off, near [ReminderTime.maxCount]) and an enabled weekly digest on the
/// longest weekday label ("Wednesday") — the shape a real, lived-in
/// install's settings look like, shared by every card built from this file
/// so each is stressed with more than a fresh-install default.
AppSettings _stressedSettings() => const AppSettings(
  backend: BackendAddress(host: 'diary.example.com', port: 8443),
  reminders: [
    ReminderTime(hour: 6, minute: 45, enabled: true),
    ReminderTime(hour: 9, minute: 0, enabled: false),
    ReminderTime(hour: 12, minute: 30, enabled: true),
    ReminderTime(hour: 15, minute: 15, enabled: false),
    ReminderTime(hour: 18, minute: 0, enabled: true),
    ReminderTime(hour: 22, minute: 30, enabled: true),
  ],
  digest: DigestTime(
    weekday: DateTime.wednesday,
    hour: 19,
    minute: 45,
    enabled: true,
  ),
);

/// The longest failure message this row realistically shows — the
/// server-envelope shape `ApiClient._errorMessage` reads out of
/// `{"error": {"message": ...}}`, not the short HTTP-status fallback — so
/// the row's `Expanded(Text(...))` next to its "Dismiss" button is stressed
/// with more than one short word.
const String _longExportError =
    'The export service is temporarily unavailable while the backend '
    'finishes a maintenance window. Please try again in a few minutes.';

/// Fixes [ExportRow] into its error state without driving a real download —
/// [ExportController.export] does genuine `dart:io` work a widget test's
/// pump loop cannot settle (see `export_row_test.dart`'s file doc comment),
/// and the sweep only needs the state, not the transition into it.
class _StressedExportController extends Notifier<ExportState> {
  @override
  ExportState build() => const ExportError(_longExportError);
}

/// A `StatefulShellRoute` wired to nothing but [AppShell] itself and four
/// empty branches — the minimal scaffolding
/// `StatefulNavigationShell.currentIndex`/`goBranch` need to exist at all.
///
/// Deliberately not the app's own `routerProvider` (`lib/app.dart`): that
/// router's four branches are the real `TodayScreen`, `InsightsScreen`,
/// `CalendarScreen` and `SettingsScreen`, and `StatefulShellRoute.
/// indexedStack` keeps every branch's navigator mounted at once (that is how
/// each tab keeps its own state across a switch) — so a sweep built on the
/// real router would measure all four full screens simultaneously, not the
/// shell. Those screens are each other areas' own surfaces (or, for
/// `SettingsScreen`, this file's own separate case); this router's branches
/// stay empty so this case measures exactly one thing, `AppShell`'s own
/// `NavigationBar` and its four labels ("Today", "Insights", "Calendar",
/// "Settings" — the longest of the four, and exactly the kind of label that
/// breaks at 2x).
GoRouter _shellTestRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        for (final path in const ['/', '/insights', '/calendar', '/settings'])
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: path,
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
      ],
    ),
  ],
);

/// `lib/features/settings/ and lib/features/shell/`.
final settingsShell = ScreenArea(
  name: 'settings shell',
  cases: [
    ScreenCase(
      name: 'RemindersCard',
      source: 'features/settings/reminders_card.dart',
      build: () => Harness(settings: _stressedSettings()).scope(
        MaterialApp(
          theme: buildLightTheme(),
          home: const Scaffold(body: RemindersCard()),
        ),
      ),
    ),
    ScreenCase(
      name: 'DigestCard',
      source: 'features/settings/digest_card.dart',
      build: () => Harness(settings: _stressedSettings()).scope(
        MaterialApp(
          theme: buildLightTheme(),
          home: const Scaffold(body: DigestCard()),
        ),
      ),
    ),
    ScreenCase(
      name: 'ExportRow',
      source: 'features/settings/export/export_row.dart',
      build: () {
        final harness = Harness();
        return ProviderScope(
          overrides: [
            ...harness.baseOverrides,
            exportControllerProvider.overrideWith(
              _StressedExportController.new,
            ),
          ],
          retry: Harness.noRetry,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: const Scaffold(body: ExportRow()),
          ),
        );
      },
    ),
    ScreenCase(
      name: 'SettingsScreen',
      source: 'features/settings/settings_screen.dart',
      build: () =>
          Harness(
            settings: _stressedSettings(),
            requireAuth: true,
          ).scope(
            MaterialApp(theme: buildLightTheme(), home: const SettingsScreen()),
          ),
    ),
    ScreenCase(
      name: 'AppShell',
      source: 'features/shell/app_shell.dart',
      build: () => MaterialApp.router(
        theme: buildLightTheme(),
        routerConfig: _shellTestRouter(),
      ),
    ),
  ],
  unswept: const {},
);
