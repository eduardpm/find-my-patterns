import 'package:find_my_patterns/core/config/app_config.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/widgets/server_form.dart';
import 'package:find_my_patterns/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/harness.dart';

void main() {
  /// Gives the test a tall surface so every card on the Settings list is
  /// built; otherwise the ones below the fold never render and cannot be
  /// found.
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('shows the server, appearance, topics and about sections', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(Harness().scope(_app()));
    await tester.pumpAndSettle();

    expect(find.text('Server'), findsOneWidget);
    expect(find.byType(ServerForm), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Topics and aliases'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(
      find.text('${AppConfig.appName} ${AppConfig.appVersion}'),
      findsOneWidget,
    );
  });

  testWidgets('changing the appearance stores it', (tester) async {
    final harness = Harness();
    useTallScreen(tester);
    await tester.pumpWidget(harness.scope(_app()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(harness.store.savedThemeModes.single, ThemeModeSetting.dark);
  });

  testWidgets('hides the sign-out section when the app is not gated', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(Harness().scope(_app()));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('offers sign out when the app is gated', (tester) async {
    final harness = Harness(
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
      requireAuth: true,
    );
    useTallScreen(tester);
    await tester.pumpWidget(harness.scope(_app()));
    await tester.pumpAndSettle();

    expect(find.text('Session'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(harness.adapter.requests.last.method, 'DELETE');
  });

  testWidgets('the topics card opens the topics route', (tester) async {
    // A throwaway router built just for this test, rather than the app's own
    // one: the real route is registered in lib/app.dart, which this feature
    // does not own, so this only proves the card pushes the constant this
    // screen promises to use.
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SettingsScreen()),
        GoRoute(
          path: SettingsScreen.topicsRoute,
          builder: (context, state) =>
              const Scaffold(body: Text('topics destination')),
        ),
      ],
    );
    useTallScreen(tester);
    await tester.pumpWidget(
      Harness().scope(MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Topics and aliases'));
    await tester.pumpAndSettle();

    expect(find.text('topics destination'), findsOneWidget);
  });
}

Widget _app() => const MaterialApp(home: SettingsScreen());
