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
}
