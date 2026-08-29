import 'dart:io';

import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/settings/export/export_controller.dart';
import 'package:find_my_patterns/features/settings/export/export_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_http.dart';
import '../../../support/harness.dart';

/// Widget-level coverage for [ExportRow]: the dialog opens with both format
/// options, dismissing it without choosing triggers nothing, tapping an
/// option reaches the network with the right format, and the error state
/// renders with a way to dismiss it.
///
/// What this file deliberately does *not* re-prove: that `export()` itself
/// downloads, writes the file, and reaches the share sheet — `export()` does
/// genuine `dart:io` work (a real file write) that a widget test's
/// fake-async pump loop cannot drive to completion once the call chain is
/// anchored to a gesture-dispatched `Future` under it, and `pumpAndSettle`
/// cannot be used to work around that either: the row shows an indeterminate
/// `CircularProgressIndicator` while the export is in flight, and an
/// indeterminate spinner never lets `pumpAndSettle` see "no frame pending".
/// That whole pipeline — download, write, share, and both failure paths —
/// is covered end to end, deterministically and without any of the above, by
/// `test/features/settings/export/export_controller_test.dart`, driving the
/// same `ExportController` this row reads.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('export-row-test-');
  });
  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Wraps [ExportRow] with a configured backend and exports staged in
  /// [tempDir], so a tap that reaches the network never blocks on
  /// `BackendNotConfigured` first.
  Widget appFor(FakeHttpAdapter adapter) {
    final harness = Harness(
      adapter: adapter,
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
    );
    return ProviderScope(
      overrides: [
        ...harness.baseOverrides,
        exportCacheDirectoryProvider.overrideWithValue(() async => tempDir),
      ],
      retry: Harness.noRetry,
      child: const MaterialApp(home: Scaffold(body: ExportRow())),
    );
  }

  testWidgets('shows the row with a share affordance', (tester) async {
    await tester.pumpWidget(appFor(FakeHttpAdapter([])));

    expect(find.text('Export my diary'), findsOneWidget);
    expect(find.byIcon(Icons.share), findsOneWidget);
  });

  testWidgets('tapping opens a choice of both export formats', (
    tester,
  ) async {
    await tester.pumpWidget(appFor(FakeHttpAdapter([])));

    await tester.tap(find.text('Export my diary'));
    await tester.pumpAndSettle();

    expect(find.text('Export as'), findsOneWidget);
    expect(find.text('Markdown (.md)'), findsOneWidget);
    expect(find.text('JSON (.json)'), findsOneWidget);
  });

  testWidgets('dismissing the format choice without choosing exports nothing', (
    tester,
  ) async {
    final adapter = FakeHttpAdapter([]);
    await tester.pumpWidget(appFor(adapter));

    await tester.tap(find.text('Export my diary'));
    await tester.pumpAndSettle();
    // Tap the modal barrier, outside the dialog, to dismiss it unanswered.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(adapter.requests, isEmpty);
  });

  testWidgets(
    'choosing a format starts the export: the row shows progress and the '
    'right format reaches the network',
    (tester) async {
      // A transport failure, not a real reply: it fails before `export()`
      // ever reaches the (genuinely un-driveable, see the file doc comment)
      // file write, so the row settles back down on its own via an ordinary
      // `pumpAndSettle` below, without needing `runAsync`.
      final adapter = FakeHttpAdapter([const FakeReply.networkError()]);
      await tester.pumpWidget(appFor(adapter));

      await tester.tap(find.text('Export my diary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markdown (.md)'));
      // One frame is enough: `ExportController.export` sets the in-progress
      // state as its very first statement, before any `await`.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.share), findsNothing);

      // Let the (failing) request resolve so the row settles back to an
      // error rather than leaving a dangling timer behind for the next test.
      await tester.pumpAndSettle();
      expect(adapter.requests.single.uri.queryParameters, {
        'format': 'markdown',
      });
    },
  );

  testWidgets(
    'shows the failure message and a way to dismiss it when the export fails',
    (tester) async {
      final adapter = FakeHttpAdapter([const FakeReply(500)]);
      await tester.pumpWidget(appFor(adapter));

      await tester.tap(find.text('Export my diary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JSON (.json)'));
      await tester.pumpAndSettle();

      expect(find.textContaining('500'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.textContaining('500'), findsNothing);
    },
  );
}
