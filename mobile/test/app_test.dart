import 'package:find_my_patterns/app.dart';
import 'package:find_my_patterns/core/config/app_config.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/auth/login_screen.dart';
import 'package:find_my_patterns/features/shell/app_shell.dart';
import 'package:find_my_patterns/features/today/today_screen.dart';
import 'package:flutter/material.dart';
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
