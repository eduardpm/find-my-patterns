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

/// A realistic `NetworkFailure` message, not an invented one: `ApiClient.
/// _networkMessage` builds exactly `'Could not reach the server (${e.message
/// ?? e.type.name})'`, and `e.message` for a DNS failure is `dart:io`'s own
/// `SocketException.toString()` — this is that real format, for the same
/// host `_stressedSettings` configures, the everyday way a self-hosted
/// backend (Article 8) goes briefly unreachable. Chosen over a shorter,
/// fabricated server-envelope message: every real message this backend's
/// `ErrorEnvelopeFilter` emits (`backend/src/common/http-exception.filter.
/// ts`) is short and technical ("Entry not found", "Field required: date"),
/// so a long one has to come from a genuine failure shape instead, not
/// invented prose.
const String _longExportError =
    'Could not reach the server (SocketException: Failed host lookup: '
    "'diary.example.com' (OS Error: No address associated with hostname, "
    'errno = 7))';

/// Fixes [ExportRow] into its error state without driving a real download —
/// [ExportController.export] does genuine `dart:io` work a widget test's
/// pump loop cannot settle (see `export_row_test.dart`'s file doc comment),
/// and the sweep only needs the state, not the transition into it.
///
/// Extends [ExportController] itself, not `Notifier<ExportState>` — Riverpod
/// types `NotifierProvider.overrideWith` to the provider's own notifier
/// class exactly, so a sibling implementation of the same base is not
/// assignable to it.
class _StressedExportController extends ExportController {
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
            // A `SingleChildScrollView`, not a bare `Scaffold(body: ...)`:
            // the real caller is `SettingsScreen`'s `ListView`, which never
            // imposes a height ceiling on one item -- a tall card just
            // pushes the rest of the list down. A bare `Scaffold.body`
            // does impose one (the viewport height), and the sweep's own
            // 3000dp-tall test surface plus this row's realistic
            // `NetworkFailure` message (several wrapped lines at 2x) is
            // enough to exceed even that, throwing a `RenderFlex` overflow
            // that only exists because this case's wrapper is harsher than
            // the real screen -- the mirror image of #163's harness being
            // *too generous*. Scrolling matches the real container instead
            // of fighting it.
            home: const Scaffold(
              body: SingleChildScrollView(child: ExportRow()),
            ),
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
      // All four `NavigationBar` destinations share one 320-360dp bar in
      // four equal-width columns; three of the four labels ("Insights",
      // "Calendar", "Settings") do not fit their ~80-90px column even at
      // text scale 1.0, before any dynamic-type scaling. `NavigationBar`
      // gives every destination an equal share with no public way to widen
      // one over its siblings (confirmed by reading
      // `_NavigationDestinationLayoutDelegate.performLayout` in the Flutter
      // SDK), and `NavigationDestinationLabelBehavior.alwaysHide` does not
      // help -- it only fades the label's opacity, the label is still laid
      // out at full size underneath either way. Same family as #169/#172:
      // a fixed-segment control that cannot fit its labels at this width,
      // whatever its padding -- a control or information-architecture
      // decision, not a mechanical `Flexible`/`Wrap` fix. Filed as #178
      // with the measured numbers for all six cells (every one fails).
      knownFailures: const {
        '320x1.0': '#178',
        '320x1.3': '#178',
        '320x2.0': '#178',
        '360x1.0': '#178',
        '360x1.3': '#178',
        '360x2.0': '#178',
      },
    ),
  ],
  unswept: const {},
);
