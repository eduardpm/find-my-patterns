// M-3 (#48): the product constitution forbids paywalling writing, reading
// back, or export -- so there must be no lock anywhere on entries, feelings,
// the calendar, or export. The backend asserts this as a table
// (`backend/tests/contract/free-paid-boundary.test.ts`'s "never gated"
// describe block); this file is the client's own assertion of the same
// rule, run under `Tier.free` explicitly so there is no ambiguity about
// which tier is under test.
//
// Each screen below is mounted with its own real dependencies (the same
// fakes and JSON fixtures its own test file already uses) rather than a
// stub, specifically so this is a genuine rendering of the screen a free
// account actually sees -- not a check that could pass by accident because
// nothing ever got far enough to build.

import 'dart:io';

import 'package:find_my_patterns/core/audio/diary_audio_recorder.dart';
import 'package:find_my_patterns/core/auth/tier.dart';
import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/core/widgets/premium_lock.dart';
import 'package:find_my_patterns/features/calendar/calendar_controller.dart';
import 'package:find_my_patterns/features/calendar/calendar_screen.dart';
import 'package:find_my_patterns/features/compose/entry_composer_screen.dart';
import 'package:find_my_patterns/features/entry/entry_detail_screen.dart';
import 'package:find_my_patterns/features/settings/export/export_controller.dart';
import 'package:find_my_patterns/features/settings/export/export_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/audio/fake_audio_recorder_plugin.dart';
import '../../support/fake_http.dart';
import '../../support/harness.dart';
import '../calendar/json_fixtures.dart' as calendar_fixtures;
import '../compose/json_fixtures.dart' as compose_fixtures;
import '../entry/json_fixtures.dart' as entry_fixtures;

/// Asserts [tester]'s currently-pumped tree carries no lock at all: neither
/// the shared [PremiumLock] widget, nor its lock glyph, nor the word
/// "Premium" anywhere a reader could see it.
void expectNoLock(WidgetTester tester) {
  expect(find.byType(PremiumLock), findsNothing);
  expect(find.byIcon(Icons.lock_outline), findsNothing);
  expect(find.textContaining('Premium'), findsNothing);
}

void main() {
  const backend = AppSettings(backend: BackendAddress(host: '10.0.2.2'));

  group('calendar', () {
    testWidgets('no lock anywhere on the month grid', (tester) async {
      final harness = Harness(
        settings: backend,
        tier: Tier.free,
        adapter: FakeHttpAdapter([
          FakeReply(200, body: calendar_fixtures.feelingsCatalogJson()),
          FakeReply(
            200,
            body: calendar_fixtures.monthlySummaryJson(
              month: '2026-08',
              days: [
                calendar_fixtures.daySummaryJson(
                  date: '2026-08-05',
                  feelings: const ['happy'],
                  intensity: 3,
                ),
              ],
            ),
          ),
        ]),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            requireAuthProvider.overrideWithValue(harness.requireAuth),
            settingsStoreProvider.overrideWithValue(harness.store),
            apiClientProvider.overrideWithValue(harness.client),
            calendarNowProvider.overrideWithValue(DateTime(2026, 8, 15)),
          ],
          child: const MaterialApp(home: CalendarScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Calendar'), findsOneWidget);
      expectNoLock(tester);
    });
  });

  group('writing an entry, and the feeling vocabulary it offers', () {
    testWidgets('no lock anywhere on the composer', (tester) async {
      final harness = Harness(
        settings: backend,
        tier: Tier.free,
        adapter: FakeHttpAdapter([
          FakeReply(200, body: compose_fixtures.feelingsCatalogJson()),
          FakeReply(200, body: compose_fixtures.guidingQuestionsJson()),
          FakeReply(200, body: compose_fixtures.insightsJson()),
        ]),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.baseOverrides,
          child: MaterialApp(
            home: EntryComposerScreen(
              recorder: DiaryAudioRecorder(
                plugin: FakeAudioRecorderPlugin(),
                cacheDirectory: () async => Directory.systemTemp,
              ),
              transcriptionDelay: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The feeling vocabulary this same fetch loaded is on this screen's
      // guided/pairing steps -- there is no separate "feelings" screen to
      // mount, the same way there is no separate "writing" fetch to prove
      // against; this one screen's own dependencies already cover both.
      expectNoLock(tester);
    });
  });

  group('reading an entry back', () {
    testWidgets('no lock anywhere on entry detail', (tester) async {
      final harness = Harness(
        settings: backend,
        tier: Tier.free,
        adapter: FakeHttpAdapter([
          FakeReply(200, body: entry_fixtures.feelingsCatalogJson()),
          FakeReply(200, body: entry_fixtures.entryJson()),
          FakeReply(200, body: entry_fixtures.insightsJson()),
          FakeReply(200, body: {'echoes': <Object?>[]}),
        ]),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            requireAuthProvider.overrideWithValue(harness.requireAuth),
            settingsStoreProvider.overrideWithValue(harness.store),
            apiClientProvider.overrideWithValue(harness.client),
          ],
          child: const MaterialApp(
            home: EntryDetailScreen(
              entryId: 'entry-1',
              entryDate: '2026-08-05',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expectNoLock(tester);
    });
  });

  group('export', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('free-features-export-');
    });
    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('no lock anywhere on the export row, open or closed', (
      tester,
    ) async {
      final harness = Harness(
        settings: backend,
        tier: Tier.free,
        adapter: FakeHttpAdapter([]),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...harness.baseOverrides,
            exportCacheDirectoryProvider.overrideWithValue(
              () async => tempDir,
            ),
          ],
          retry: Harness.noRetry,
          child: const MaterialApp(home: Scaffold(body: ExportRow())),
        ),
      );
      await tester.pumpAndSettle();
      expectNoLock(tester);

      await tester.tap(find.text('Export my diary'));
      await tester.pumpAndSettle();

      // The format-choice dialog is the row's one other state -- still no
      // lock, and still both formats genuinely offered.
      expect(find.text('Markdown (.md)'), findsOneWidget);
      expect(find.text('JSON (.json)'), findsOneWidget);
      expectNoLock(tester);
    });
  });
}
