import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_controller.dart';
import 'core/config/app_config.dart';
import 'core/config/config_providers.dart';
import 'core/network/network_providers.dart';
import 'core/notifications/reminder_providers.dart';
import 'core/notifications/reminder_schedule.dart';
import 'core/settings/settings.dart';
import 'core/settings/settings_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/calendar/day_entries_screen.dart';
import 'features/compose/entry_composer_screen.dart';
import 'features/entry/entry_detail_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/today/today_screen.dart';
import 'features/topics/topics_screen.dart';

/// Re-runs the router's redirect whenever the auth state moves.
///
/// The router itself is never rebuilt: replacing a `GoRouter` mid-session
/// leaves the visible tree wired to the dead instance.
class AuthRefreshListenable extends ChangeNotifier {
  /// Starts listening to [authProvider] on [ref].
  AuthRefreshListenable(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
  }
}

/// The app's navigation graph, created exactly once.
///
/// The four tabs live in a `StatefulShellRoute` so each keeps its own state.
/// The login screen sits above them and is only reachable when
/// [requireAuthProvider] is on; with it off, the redirect is a no-op and the
/// shell is the whole app.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = AuthRefreshListenable(ref);
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      if (!ref.read(requireAuthProvider)) return null;
      final loggingIn = state.matchedLocation == '/login';
      return switch (ref.read(authProvider)) {
        AuthStatus.signedOut when !loggingIn => '/login',
        AuthStatus.signedIn when loggingIn => '/',
        _ => null,
      };
    },
    routes: [
      // Each branch needs a distinct path: `goBranch` navigates to the branch's
      // own route, so four branches sharing '/' would make tab switching a
      // silent no-op.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const TodayScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/insights',
                builder: (context, state) => const InsightsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (context, state) => const CalendarScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      // Above the shell rather than inside it. Writing an entry, reading one,
      // and editing the topic list are all things you finish and leave, so they
      // cover the tab bar instead of offering a way out of the middle of them.
      GoRoute(
        path: '/compose',
        builder: (context, state) => const EntryComposerScreen(),
      ),
      GoRoute(
        // Keyed on the date as well as the id: the evidence trail on a pattern
        // card carries both, and making the route take both saves a round trip
        // whose only purpose would be to learn something the caller already has.
        path: '/entry/:entryId/:entryDate',
        builder: (context, state) => EntryDetailScreen(
          entryId: state.pathParameters['entryId'] ?? '',
          entryDate: state.pathParameters['entryDate'] ?? '',
        ),
      ),
      GoRoute(
        path: '/calendar/day/:date',
        builder: (context, state) =>
            DayEntriesScreen(date: state.pathParameters['date'] ?? ''),
      ),
      GoRoute(
        path: SettingsScreen.topicsRoute,
        builder: (context, state) => TopicsScreen(onClose: () => context.pop()),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

/// The root widget: theme, router, and the one startup pass.
class FindMyPatternsApp extends ConsumerStatefulWidget {
  /// Creates the root widget.
  const FindMyPatternsApp({super.key});

  @override
  ConsumerState<FindMyPatternsApp> createState() => _FindMyPatternsAppState();
}

class _FindMyPatternsAppState extends ConsumerState<FindMyPatternsApp> {
  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  /// Waits for settings to load, points the HTTP core at the stored address,
  /// then lets the auth state machine decide splash, login, or shell.
  Future<void> _restore() async {
    final settings = await ref.read(settingsProvider.future);
    if (!mounted) return;
    ref.read(apiClientProvider).configure(settings.backend);
    await ref.read(authProvider.notifier).restore();
    if (!mounted) return;
    await _armReminders(settings.reminders);
  }

  /// Initialises the reminder plugin, re-arms whichever reminders are
  /// currently enabled, and asks whether the app was launched by tapping one.
  ///
  /// The order matters: the plugin has to be initialised before a launch tap
  /// can be read.
  ///
  /// This never requests the notification permission itself — that only
  /// happens when the user turns a reminder on from Settings
  /// (`RemindersController.save`), not unconditionally on every cold start.
  /// Rescheduling from the stored settings here is what makes a reminder
  /// survive the app itself being restarted, alongside the native
  /// `flutter_local_notifications` boot receivers already declared in the
  /// Android manifest, which re-arm the same alarms across an actual device
  /// reboot without this method's help.
  Future<void> _armReminders(List<ReminderTime> reminders) async {
    final service = ref.read(reminderServiceProvider);
    await service.initialize();
    final slots = [
      for (final reminder in reminders)
        if (reminder.enabled) ReminderSlot(reminder.hour, reminder.minute),
    ];
    if (slots.isNotEmpty) {
      await service.scheduleAll(slots: slots);
    }
    if (!mounted) return;
    await ref.read(openComposerSignalProvider.notifier).checkLaunchTap();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();

    // Tapping a reminder opens the composer, from a cold start or while the app
    // is already running. The signal is a counter rather than a flag so that a
    // second tap re-opens the composer even when the first one already did:
    // with a boolean, the state would already be `true` and nothing would move.
    ref.listen(openComposerSignalProvider, (previous, next) {
      if (previous == next) return;
      ref.read(routerProvider).push('/compose');
    });

    return MaterialApp.router(
      title: AppConfig.appName,
      theme: buildLightTheme(palette: settings.palette),
      darkTheme: buildDarkTheme(palette: settings.palette),
      themeMode: themeModeSettingToMaterial(settings.themeMode),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => auth == AuthStatus.loading
          ? const SplashScreen()
          : child ?? const SizedBox.shrink(),
    );
  }
}

/// What the user sees while the stored settings and session are being checked.
class SplashScreen extends StatelessWidget {
  /// Creates the splash screen.
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              AppConfig.appName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
