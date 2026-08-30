import 'package:find_my_patterns/core/auth/auth_controller.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/widgets/server_form.dart';
import 'package:find_my_patterns/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';

void main() {
  const configured = AppSettings(backend: BackendAddress(host: '10.0.2.2'));

  Finder fieldLabelled(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byType(TextField),
  );

  testWidgets('offers the server form when nothing is configured yet', (
    tester,
  ) async {
    await tester.pumpWidget(
      Harness(requireAuth: true).scope(const MaterialApp(home: LoginScreen())),
    );
    await tester.pumpAndSettle();

    // This is the dead end the old screen had: no server, no password field,
    // and no way to reach Settings.
    expect(find.byType(ServerForm), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(
      find.textContaining('point this app at your server'),
      findsOneWidget,
    );
  });

  testWidgets('moves to the password field once a server is saved', (
    tester,
  ) async {
    await tester.pumpWidget(
      Harness(requireAuth: true).scope(const MaterialApp(home: LoginScreen())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(fieldLabelled('Host'), '10.0.2.2');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(ServerForm), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('shows the password field when a server is configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      Harness(
        settings: configured,
        requireAuth: true,
      ).scope(const MaterialApp(home: LoginScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.textContaining('http://10.0.2.2:8000'), findsOneWidget);
  });

  testWidgets('lets the user go back and change the server', (tester) async {
    await tester.pumpWidget(
      Harness(
        settings: configured,
        requireAuth: true,
      ).scope(const MaterialApp(home: LoginScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('change'));
    await tester.pumpAndSettle();

    expect(find.byType(ServerForm), findsOneWidget);
  });

  testWidgets('signs in with a correct password', (tester) async {
    final harness = Harness(
      settings: configured,
      requireAuth: true,
      adapter: FakeHttpAdapter.always(const FakeReply(200, body: {})),
    );
    late AuthStatus status;
    await tester.pumpWidget(
      harness.scope(
        MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              status = ref.watch(authProvider);
              return const LoginScreen();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(status, AuthStatus.signedIn);
  });

  testWidgets('shows the reason a password was rejected', (tester) async {
    final harness = Harness(
      settings: configured,
      requireAuth: true,
      adapter: FakeHttpAdapter.always(const FakeReply(401)),
    );
    await tester.pumpWidget(
      harness.scope(const MaterialApp(home: LoginScreen())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    // The message, not "Unauthorized: ..." with the class name in it.
    expect(find.text('Your session has expired'), findsOneWidget);
    expect(find.textContaining('Unauthorized'), findsNothing);
  });

  testWidgets('shows a spinner while signing in', (tester) async {
    final harness = Harness(
      settings: configured,
      requireAuth: true,
      adapter: FakeHttpAdapter.always(const FakeReply(200, body: {})),
    );
    await tester.pumpWidget(
      harness.scope(const MaterialApp(home: LoginScreen())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('submitting from the keyboard signs in', (tester) async {
    final harness = Harness(
      settings: configured,
      requireAuth: true,
      adapter: FakeHttpAdapter.always(const FakeReply(200, body: {})),
    );
    await tester.pumpWidget(
      harness.scope(const MaterialApp(home: LoginScreen())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(harness.adapter.requests, isNotEmpty);
  });

  group('dynamic type at the required matrix (#155)', () {
    // A first-run user sees this screen at whatever text scale they
    // already have set, so `login_screen.dart:127`'s error-banner `Row`
    // (already `Flexible`-protected) and the "Connected to <origin> --
    // change" `TextButton` (`:149`, an unbounded-length host the user
    // themselves typed into `ServerForm`) are both measured, not assumed.
    const longHostConfigured = AppSettings(
      backend: BackendAddress(
        host: 'a-fairly-long-self-hosted-server-hostname.example.internal',
        port: 8443,
      ),
    );

    Future<void> pumpAtScale(
      WidgetTester tester,
      Widget app, {
      required double width,
      required double scale,
    }) async {
      tester.view.physicalSize = Size(width, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: app,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          'the server form (no backend configured) renders with no '
          'overflow at ${width.toInt()}dp / ${scale}x',
          (tester) async {
            await pumpAtScale(
              tester,
              Harness(
                requireAuth: true,
              ).scope(const MaterialApp(home: LoginScreen())),
              width: width,
              scale: scale,
            );

            expect(tester.takeException(), isNull);
            expect(find.byType(ServerForm), findsOneWidget);
          },
        );

        testWidgets(
          'the password field (backend configured, with a long host) '
          'renders with no overflow at ${width.toInt()}dp / ${scale}x',
          (tester) async {
            await pumpAtScale(
              tester,
              Harness(
                settings: longHostConfigured,
                requireAuth: true,
              ).scope(const MaterialApp(home: LoginScreen())),
              width: width,
              scale: scale,
            );

            expect(tester.takeException(), isNull);
            expect(find.text('Sign in'), findsOneWidget);
            expect(
              find.textContaining(
                'a-fairly-long-self-hosted-server-hostname',
              ),
              findsOneWidget,
            );
          },
        );
      }
    }

    testWidgets(
      'the rejected-password error banner renders with no overflow at '
      '320dp/2x',
      (tester) async {
        final harness = Harness(
          settings: longHostConfigured,
          requireAuth: true,
          adapter: FakeHttpAdapter.always(const FakeReply(401)),
        );
        await pumpAtScale(
          tester,
          harness.scope(const MaterialApp(home: LoginScreen())),
          width: 320,
          scale: 2,
        );

        await tester.enterText(find.byType(TextField), 'wrong');
        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Your session has expired'), findsOneWidget);
      },
    );

    testWidgets('the "Sign in" button stays at least 48dp at 320dp/2x', (
      tester,
    ) async {
      await pumpAtScale(
        tester,
        Harness(
          settings: longHostConfigured,
          requireAuth: true,
        ).scope(const MaterialApp(home: LoginScreen())),
        width: 320,
        scale: 2,
      );

      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(FilledButton));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });
}
