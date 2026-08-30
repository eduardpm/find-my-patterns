import 'package:find_my_patterns/app.dart';
import 'package:find_my_patterns/core/config/app_config.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/auth/login_screen.dart';
import 'package:find_my_patterns/features/insights/digest_screen.dart';
import 'package:find_my_patterns/features/insights/insights_screen.dart';
import 'package:find_my_patterns/features/shell/app_shell.dart';
import 'package:find_my_patterns/features/today/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_http.dart';
import 'support/harness.dart';

void main() {
  const configured = AppSettings(backend: BackendAddress(host: '10.0.2.2'));

  group('ungated app', () {
    testWidgets('boots straight into the shell', (tester) async {
      await tester.pumpWidget(Harness().scope(const FindMyPatternsApp()));
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      // The four tabs the diary actually has, in order, with Today showing.
      expect(find.byType(TodayScreen), findsOneWidget);
      for (final tab in ['Today', 'Insights', 'Calendar', 'Settings']) {
        expect(find.text(tab), findsWidgets, reason: '$tab tab is missing');
      }
    });

    testWidgets('points the HTTP core at the stored address on startup', (
      tester,
    ) async {
      final harness = Harness(settings: configured);
      await tester.pumpWidget(harness.scope(const FindMyPatternsApp()));
      await tester.pumpAndSettle();
      expect(harness.client.backend.host, '10.0.2.2');
    });

    testWidgets(
      'cold start cancels a leaked reminder alarm no current setting names '
      '(#153)',
      (tester) async {
        // No enabled reminder anywhere in settings -- the default,
        // both-off `kDefaultReminders` -- yet the platform already has an
        // alarm armed at 12:00, the exact shape of the leak the issue
        // found: a slot id with no corresponding setting anywhere in the
        // UI, left over from some earlier configuration or a lost race.
        final harness = Harness();
        harness.remindersPlugin.pendingIds.add(12 * 60);

        await tester.pumpWidget(harness.scope(const FindMyPatternsApp()));
        await tester.pumpAndSettle();

        expect(harness.remindersPlugin.cancelledIds, contains(12 * 60));
        expect(harness.remindersPlugin.pendingIds, isEmpty);
      },
    );

    testWidgets('applies the stored theme mode', (tester) async {
      await tester.pumpWidget(
        Harness(
          settings: const AppSettings(themeMode: ThemeModeSetting.dark),
        ).scope(const FindMyPatternsApp()),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(app.title, AppConfig.appName);
    });

    testWidgets('changing the theme in Settings repaints the app', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(Harness().scope(const FindMyPatternsApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(
        Theme.of(tester.element(find.text('Advanced'))).brightness,
        Brightness.dark,
      );
    });
  });

  group('gated app', () {
    testWidgets('shows the login screen when there is no session', (
      tester,
    ) async {
      await tester.pumpWidget(
        Harness(
          settings: configured,
          requireAuth: true,
          adapter: FakeHttpAdapter.always(const FakeReply(401)),
        ).scope(const FindMyPatternsApp()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('a stored session goes straight to the shell', (tester) async {
      await tester.pumpWidget(
        Harness(
          settings: configured,
          requireAuth: true,
          adapter: FakeHttpAdapter.always(const FakeReply(200, body: {})),
        ).scope(const FindMyPatternsApp()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('signing in moves from the login screen to the shell', (
      tester,
    ) async {
      await tester.pumpWidget(
        Harness(
          settings: configured,
          requireAuth: true,
          adapter: FakeHttpAdapter([
            const FakeReply(401), // the session probe at startup
            const FakeReply(200, body: {}), // the sign-in
          ]),
        ).scope(const FindMyPatternsApp()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'hunter2');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('an unconfigured server lands on the login screen, not a dead '
        'end', (tester) async {
      await tester.pumpWidget(
        Harness(requireAuth: true).scope(const FindMyPatternsApp()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Host'), findsOneWidget);
    });
  });

  group('first-pattern notification tap-through (L-3/#38)', () {
    testWidgets(
      'a warm tap switches the Insights shell branch, not a stacked screen',
      (tester) async {
        final harness = Harness();
        await tester.pumpWidget(harness.scope(const FindMyPatternsApp()));
        await tester.pumpAndSettle();
        expect(find.byType(TodayScreen), findsOneWidget);
        expect(find.byType(InsightsScreen), findsNothing);

        harness.remindersPlugin.fireTap(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: 'first_pattern',
          ),
        );
        await tester.pumpAndSettle();

        // `AppShell` (and its bottom nav bar) is still the one screen on
        // screen -- this switched the already-showing shell's branch
        // rather than pushing a second Insights screen on top of it.
        expect(find.byType(AppShell), findsOneWidget);
        expect(find.byType(InsightsScreen), findsOneWidget);
        expect(find.byType(TodayScreen), findsNothing);
      },
    );

    testWidgets(
      'a cold-start launch tap opens straight to Insights',
      (tester) async {
        final harness = Harness();
        harness.remindersPlugin.launchDetails =
            const NotificationAppLaunchDetails(
              true,
              notificationResponse: NotificationResponse(
                notificationResponseType:
                    NotificationResponseType.selectedNotification,
                payload: 'first_pattern',
              ),
            );

        await tester.pumpWidget(harness.scope(const FindMyPatternsApp()));
        await tester.pumpAndSettle();

        expect(find.byType(AppShell), findsOneWidget);
        expect(find.byType(InsightsScreen), findsOneWidget);
      },
    );

    testWidgets(
      'a reminder tap still opens the composer, not Insights',
      (tester) async {
        final harness = Harness();
        await tester.pumpWidget(harness.scope(const FindMyPatternsApp()));
        await tester.pumpAndSettle();

        harness.remindersPlugin.fireTap(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: '540',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(InsightsScreen), findsNothing);
        expect(find.text('New entry'), findsOneWidget);
      },
    );
  });

  group('weekly digest notification tap-through (R-2)', () {
    final digestJson = {
      'empty': false,
      'week': '2026-08-24',
      'entry_count': 3,
      'highlight': {
        'pattern_ref': 'p1',
        'kind': 'forward',
        'topic': 'reading',
        'week_count': 3,
        'lift': 1.5,
        'sentence': 'reading came up in 3 entries this week.',
      },
    };

    testWidgets(
      'a warm tap fetches the digest and opens the sheet for it',
      (tester) async {
        final harness = Harness(
          settings: configured,
          adapter: FakeHttpAdapter.always(FakeReply(200, body: digestJson)),
        );
        await tester.pumpWidget(harness.scope(const FindMyPatternsApp()));
        await tester.pumpAndSettle();
        expect(find.byType(DigestScreen), findsNothing);

        harness.remindersPlugin.fireTap(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: 'weekly_digest',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DigestScreen), findsOneWidget);
        expect(
          find.text('reading came up in 3 entries this week.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a premium_required response opens the digest sheet locked, not '
      'Insights and not an error (M-3, #48, task 4)',
      (tester) async {
        final harness = Harness(
          settings: configured,
          adapter: FakeHttpAdapter.always(
            FakeReply(402, body: {'error': 'premium_required'}),
          ),
        );
        await tester.pumpWidget(harness.scope(const FindMyPatternsApp()));
        await tester.pumpAndSettle();

        harness.remindersPlugin.fireTap(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: 'weekly_digest',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DigestScreen), findsOneWidget);
        expect(find.byType(InsightsScreen), findsNothing);
        expect(
          find.text('Weekly digests are a Premium feature.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a cold-start launch tap fetches the digest and opens the sheet for it',
      (tester) async {
        final harness = Harness(
          settings: configured,
          adapter: FakeHttpAdapter.always(FakeReply(200, body: digestJson)),
        );
        harness.remindersPlugin.launchDetails =
            const NotificationAppLaunchDetails(
              true,
              notificationResponse: NotificationResponse(
                notificationResponseType:
                    NotificationResponseType.selectedNotification,
                payload: 'weekly_digest',
              ),
            );

        await tester.pumpWidget(harness.scope(const FindMyPatternsApp()));
        await tester.pumpAndSettle();

        expect(find.byType(DigestScreen), findsOneWidget);
      },
    );

    testWidgets(
      'an unreachable backend opens Insights instead of a broken sheet '
      '(task 2\'s own words: never show stale content as fresh)',
      (tester) async {
        final harness = Harness(
          settings: configured,
          adapter: FakeHttpAdapter.always(const FakeReply.networkError()),
        );
        await tester.pumpWidget(harness.scope(const FindMyPatternsApp()));
        await tester.pumpAndSettle();

        harness.remindersPlugin.fireTap(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: 'weekly_digest',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DigestScreen), findsNothing);
        expect(find.byType(InsightsScreen), findsOneWidget);
      },
    );

    testWidgets('a reminder tap opens the composer, not the digest sheet', (
      tester,
    ) async {
      final harness = Harness();
      await tester.pumpWidget(harness.scope(const FindMyPatternsApp()));
      await tester.pumpAndSettle();

      harness.remindersPlugin.fireTap(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '540',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DigestScreen), findsNothing);
      expect(find.text('New entry'), findsOneWidget);
    });
  });

  group('SplashScreen', () {
    testWidgets('names the app while it loads', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SplashScreen()),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(AppConfig.appName), findsOneWidget);
    });
  });
}
