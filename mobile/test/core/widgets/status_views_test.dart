import 'package:find_my_patterns/core/widgets/status_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('LoadingView', () {
    testWidgets('shows an indicator alone', (tester) async {
      await tester.pumpWidget(host(const LoadingView()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('shows the label when given one', (tester) async {
      await tester.pumpWidget(
        host(const LoadingView(label: 'Loading entries')),
      );
      expect(find.text('Loading entries'), findsOneWidget);
    });
  });

  group('ErrorView', () {
    testWidgets('shows the message and no buttons by default', (tester) async {
      await tester.pumpWidget(host(const ErrorView(message: 'It broke')));
      expect(find.text('It broke'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Open Settings'), findsNothing);
    });

    testWidgets('offers Retry when it can retry', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        host(ErrorView(message: 'It broke', onRetry: () => retried = true)),
      );
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('offers a route to Settings when the server is unset', (
      tester,
    ) async {
      var configured = false;
      await tester.pumpWidget(
        host(
          ErrorView(
            message: 'No server address configured',
            onConfigure: () => configured = true,
          ),
        ),
      );
      await tester.tap(find.text('Open Settings'));
      expect(configured, isTrue);
    });

    testWidgets('can offer both actions at once', (tester) async {
      await tester.pumpWidget(
        host(ErrorView(message: 'x', onRetry: () {}, onConfigure: () {})),
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
    });
  });
}
