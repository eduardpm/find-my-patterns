import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_controller.dart';
import 'core/config/app_config.dart';
import 'core/config/config_providers.dart';
import 'core/diary/calendar_date.dart';
import 'core/diary/diary_providers.dart';
import 'core/diary/digest.dart';
import 'core/network/api_error.dart';
import 'core/network/network_providers.dart';
import 'core/notifications/digest_settings_controller.dart';
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
import 'features/experiments/experiment_results_screen.dart';
import 'features/insights/digest_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/premium/upgrade_screen.dart';
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
        // `date` backdates the composer (#36) -- the day view's empty state
        // and the Today nudge both push here with an explicit `YYYY-MM-DD`;
        // an absent or unparseable value falls back to today, the same rule
        // every date-shaped route parameter in this app follows.
        path: '/compose',
        builder: (context, state) => EntryComposerScreen(
          targetDate: CalendarDate.tryParse(state.uri.queryParameters['date']),
        ),
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
        // R-3b: opened from the active-experiment banner on Today and from
        // a pattern card's "Test this pattern" flow alike -- both already
        // know the experiment id, so this route is keyed on it rather than
        // needing a list to filter down to one.
        path: '/experiments/:experimentId',
        builder: (context, state) => ExperimentResultsScreen(
          experimentId: state.pathParameters['experimentId'] ?? '',
        ),
      ),
      GoRoute(
        path: SettingsScreen.topicsRoute,
        builder: (context, state) => TopicsScreen(onClose: () => context.pop()),
      ),
      GoRoute(
        // R-2: the digest sheet a tap on the weekly digest notification
        // opens. Keyed on nothing -- unlike `/entry/:entryId/:entryDate`,
        // there is only ever "this week's" digest -- and fed the [Digest]
        // already fetched by `_FindMyPatternsAppState._openDigest` through
        // `extra`, rather than fetching its own: see `DigestScreen`'s own
        // doc comment for why the fetch has to happen before this route is
        // even pushed.
        path: '/digest',
        // `extra` is `null` for exactly one reason: M-3's `_openDigest`
        // pushed here after `GET /insights/digest` answered
        // `premium_required` rather than a digest -- see `DigestScreen`'s
        // own doc comment for why that gets this same route rather than
        // the unreachable-backend fallback to Insights below.
        builder: (context, state) =>
            DigestScreen(digest: state.extra as Digest?),
      ),
      GoRoute(
        // M-3, #48: where every `PremiumLock`'s Upgrade action leads.
        path: '/upgrade',
        builder: (context, state) => const UpgradeScreen(),
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

  /// Initialises the reminder plugin, reconciles the scheduled alarms
  /// against whichever reminders are currently enabled, and asks whether the
  /// app was launched by tapping one.
  ///
  /// The order matters: the plugin has to be initialised before a launch tap
  /// can be read.
  ///
  /// This never requests the notification permission itself — that only
  /// happens when the user turns a reminder on from Settings
  /// (`RemindersController.save`), not unconditionally on every cold start.
  ///
  /// Reconciling here, not just scheduling (#153), is what repairs a
  /// reminder alarm left over from a previous run — a race between two
  /// saves, a crash mid-save, or an earlier id scheme — without the user
  /// having to visit Settings and touch a reminder themselves first: cold
  /// start is the one moment every install reliably passes through, so it's
  /// the backstop for a leak `RemindersController.save`'s own reconcile call
  /// missed. This is also what makes a reminder survive the app itself
  /// being restarted, alongside the native `flutter_local_notifications`
  /// boot receivers already declared in the Android manifest, which re-arm
  /// the same alarms across an actual device reboot without this method's
  /// help.
  Future<void> _armReminders(List<ReminderTime> reminders) async {
    final service = ref.read(reminderServiceProvider);
    await service.initialize();
    final slots = [
      for (final reminder in reminders)
        if (reminder.enabled) ReminderSlot(reminder.hour, reminder.minute),
    ];
    await service.reconcileReminders(slots: slots);
    // R-2: re-arms the weekly digest from stored settings, the same
    // survives-a-restart guarantee `reconcileReminders` above gives
    // reminders. `DigestSettingsController.rearm` also cancels it outright
    // when the digest is off, so this is safe to call unconditionally
    // rather than branching on `AppSettings.digest.enabled` here too.
    await ref.read(digestSettingsControllerProvider.notifier).rearm();
    if (!mounted) return;
    await ref.read(openComposerSignalProvider.notifier).checkLaunchTap();
    if (!mounted) return;
    // A cold start from the first-pattern celebration notification (#38)
    // is read the same way a reminder's cold start is -- see
    // `OpenInsightsSignal.checkLaunchTap`'s doc comment.
    await ref.read(openInsightsSignalProvider.notifier).checkLaunchTap();
    if (!mounted) return;
    // R-2: same cold-start handling for the weekly digest notification.
    // `_openDigest` (not a plain counter bump) is what turns this into
    // either the digest sheet or, on an unreachable backend, Insights --
    // see its own doc comment.
    await ref.read(openDigestSignalProvider.notifier).checkLaunchTap();
  }

  /// Fetches the current digest and opens the sheet for it, opens the same
  /// sheet locked when the account cannot have one, or falls back to
  /// Insights when the backend cannot answer at all.
  ///
  /// Task 2's own words: "if the digest API is unreachable at fire time, the
  /// notification simply opens Insights (never show stale content as
  /// fresh)." The fetch happens *before* navigating anywhere, specifically
  /// so this method — not [DigestScreen] — is the one place that decides
  /// which of the three destinations a tap actually leads to; a screen that
  /// tried to render its own fetch failure would either show a spinner
  /// forever or flash something digest-shaped before falling back, both of
  /// which are exactly the "stale content shown as fresh" task 2 forbids.
  ///
  /// M-3 (#48) adds the middle case: `premium_required` is not "the backend
  /// could not be reached" -- it is a definite, honest answer -- so it does
  /// not fall back to Insights either. It gets the digest route with no
  /// digest to show, which is task 4's "surface the locked state, not an
  /// error" applied to the one entry point this feature has.
  Future<void> _openDigest() async {
    final Digest digest;
    try {
      digest = await ref.read(insightsApiProvider).digest();
    } on ApiError catch (error) {
      if (!mounted) return;
      if (isPremiumRequired(error)) {
        unawaited(ref.read(routerProvider).push('/digest'));
        return;
      }
      ref.read(routerProvider).go(AppConfig.insightsPath);
      return;
    }
    if (!mounted) return;
    unawaited(ref.read(routerProvider).push('/digest', extra: digest));
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

    // Tapping the first-pattern celebration -- inline card or notification
    // alike (#38) -- switches to the Insights tab. `go`, not `push`:
    // Insights is a `StatefulShellRoute` branch (see `routerProvider`), and
    // navigating to its own route is what selects that branch, the same
    // way tapping the Insights tab in `AppShell` does; `push` would stack
    // a second Insights screen on top of the shell instead of switching to
    // the branch already showing it.
    ref.listen(openInsightsSignalProvider, (previous, next) {
      if (previous == next) return;
      ref.read(routerProvider).go(AppConfig.insightsPath);
    });

    // Tapping the weekly digest notification (R-2) opens the digest sheet --
    // or, when the backend cannot be reached to fetch it, Insights instead.
    // See [_openDigest]'s own doc comment for why that decision is made here
    // rather than left to the sheet to render its way out of.
    ref.listen(openDigestSignalProvider, (previous, next) {
      if (previous == next) return;
      unawaited(_openDigest());
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
