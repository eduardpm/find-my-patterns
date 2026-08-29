import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/core/widgets/server_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';

void main() {
  Finder fieldLabelled(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byType(TextField),
  );

  testWidgets('starts empty when no server has been configured', (
    tester,
  ) async {
    await tester.pumpWidget(Harness().wrap(const ServerForm()));
    await tester.pumpAndSettle();
    expect(find.text('Host'), findsOneWidget);
    expect(find.text('8000'), findsOneWidget);
  });

  testWidgets('fills the fields from the stored address', (tester) async {
    final harness = Harness(
      settings: const AppSettings(
        backend: BackendAddress(
          scheme: BackendScheme.https,
          host: 'home.example',
          port: 443,
        ),
      ),
    );
    await tester.pumpWidget(harness.wrap(const ServerForm()));
    await tester.pumpAndSettle();
    expect(find.text('home.example'), findsOneWidget);
    expect(find.text('443'), findsOneWidget);
  });

  testWidgets('saves a valid address and reports it', (tester) async {
    final harness = Harness();
    var saved = false;
    await tester.pumpWidget(
      harness.wrap(ServerForm(onSaved: () => saved = true)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(fieldLabelled('Host'), '10.0.2.2');
    await tester.enterText(fieldLabelled('Port'), '9000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(harness.store.savedAddresses.single.host, '10.0.2.2');
    expect(harness.store.savedAddresses.single.port, 9000);
    expect(saved, isTrue);
    expect(find.text('Server saved'), findsOneWidget);
  });

  testWidgets('shows why a bad address was refused and saves nothing', (
    tester,
  ) async {
    final harness = Harness();
    await tester.pumpWidget(harness.wrap(const ServerForm()));
    await tester.pumpAndSettle();

    await tester.enterText(fieldLabelled('Host'), '10.0.2.2');
    await tester.enterText(fieldLabelled('Port'), 'not-a-port');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not a port number'), findsOneWidget);
    expect(harness.store.savedAddresses, isEmpty);
  });

  testWidgets('refuses an empty host', (tester) async {
    final harness = Harness();
    await tester.pumpWidget(harness.wrap(const ServerForm()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter a host'), findsOneWidget);
    expect(harness.store.savedAddresses, isEmpty);
  });

  testWidgets('switching the scheme is carried into the saved address', (
    tester,
  ) async {
    final harness = Harness();
    await tester.pumpWidget(harness.wrap(const ServerForm()));
    await tester.pumpAndSettle();

    await tester.enterText(fieldLabelled('Host'), 'home.example');
    await tester.enterText(fieldLabelled('Port'), '443');
    await tester.tap(find.text('HTTPS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(harness.store.savedAddresses.single.scheme, BackendScheme.https);
  });

  testWidgets('reports a successful connection test', (tester) async {
    final harness = Harness(
      adapter: FakeHttpAdapter.always(const FakeReply(200, body: {})),
    );
    await tester.pumpWidget(harness.wrap(const ServerForm()));
    await tester.pumpAndSettle();

    await tester.enterText(fieldLabelled('Host'), '10.0.2.2');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Connected'), findsOneWidget);
  });

  testWidgets('reports a failed connection test', (tester) async {
    final harness = Harness(
      adapter: FakeHttpAdapter.always(const FakeReply.networkError()),
    );
    await tester.pumpWidget(harness.wrap(const ServerForm()));
    await tester.pumpAndSettle();

    await tester.enterText(fieldLabelled('Host'), '10.0.2.2');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach'), findsOneWidget);
  });

  testWidgets('refuses to test an invalid address', (tester) async {
    final harness = Harness();
    await tester.pumpWidget(harness.wrap(const ServerForm()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Enter a host'), findsOneWidget);
    expect(harness.adapter.requests, isEmpty);
  });

  testWidgets('resyncs when the stored address changes elsewhere', (
    tester,
  ) async {
    final harness = Harness();
    late WidgetRef ref;
    await tester.pumpWidget(
      harness.scope(
        MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, r, _) {
                ref = r;
                return const ServerForm();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await ref
        .read(settingsProvider.notifier)
        .saveBackendAddress(rawHost: 'elsewhere', rawPort: '1234');
    await tester.pumpAndSettle();

    expect(find.text('elsewhere'), findsOneWidget);
    expect(find.text('1234'), findsOneWidget);
  });
}
