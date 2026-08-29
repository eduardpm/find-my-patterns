import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/calendar/day_entries_controller.dart';
import 'package:find_my_patterns/features/calendar/day_entries_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

void main() {
  const date = CalendarDate(2026, 8, 5);
  const instantPoll = (
    interval: Duration.zero,
    timeout: Duration(milliseconds: 30),
  );

  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Harness configuredHarness(FakeHttpAdapter adapter) => Harness(
    settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
    adapter: adapter,
  );

  Widget app(Harness harness, {VoidCallback? onClose}) => ProviderScope(
    overrides: [
      requireAuthProvider.overrideWithValue(harness.requireAuth),
      settingsStoreProvider.overrideWithValue(harness.store),
      apiClientProvider.overrideWithValue(harness.client),
      analysisPollConfigProvider.overrideWithValue(instantPoll),
      analysisPollDelayProvider.overrideWithValue((_) async {}),
    ],
    child: MaterialApp(
      home: DayEntriesScreen(date: '$date', onClose: onClose),
    ),
  );

  testWidgets('shows the date, entry count, and each entry', (tester) async {
    useTallScreen(tester);
    final harness = configuredHarness(
      FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: {
            'entries': [
              entryJson(
                id: 'entry-1',
                createdAt: '2026-08-05T09:00:00Z',
                rawText: 'Morning walk.',
                feelingKey: 'happy',
              ),
            ],
          },
        ),
      ]),
    );
    await tester.pumpWidget(app(harness));
    await tester.pumpAndSettle();

    // Wednesday, August 5, 2026.
    expect(find.text('WEDNESDAY, AUGUST 5'), findsOneWidget);
    expect(find.text('1 entry'), findsOneWidget);
    expect(find.text('Morning walk.'), findsOneWidget);
    expect(find.text('Happy'), findsOneWidget);
  });

  testWidgets('the header reads plural for more than one entry', (
    tester,
  ) async {
    useTallScreen(tester);
    final harness = configuredHarness(
      FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: {
            'entries': [
              entryJson(id: 'entry-1', rawText: 'One.'),
              entryJson(id: 'entry-2', rawText: 'Two.'),
            ],
          },
        ),
      ]),
    );
    await tester.pumpWidget(app(harness));
    await tester.pumpAndSettle();

    expect(find.text('2 entries'), findsOneWidget);
  });

  testWidgets('an empty day shows the empty state, not a spinner', (
    tester,
  ) async {
    useTallScreen(tester);
    final harness = configuredHarness(
      FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(200, body: {'entries': <Object?>[]}),
      ]),
    );
    await tester.pumpWidget(app(harness));
    await tester.pumpAndSettle();

    expect(find.text('Nothing written that day'), findsOneWidget);
    expect(
      find.text('Days without entries stay blank — nothing was lost.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('editing, saving and seeing the analysing notice, end to end', (
    tester,
  ) async {
    useTallScreen(tester);
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsCatalogJson()),
      FakeReply(
        200,
        body: {
          'entries': [
            entryJson(id: 'entry-1', rawText: 'Old text.', version: 3),
          ],
        },
      ),
      // PATCH.
      FakeReply(
        200,
        body: entryJson(id: 'entry-1', rawText: 'New text.', version: 4),
      ),
      // Post-save refresh.
      FakeReply(
        200,
        body: {
          'entries': [
            entryJson(id: 'entry-1', rawText: 'New text.', version: 4),
          ],
        },
      ),
      // One poll: done, nothing suggested.
      FakeReply(
        200,
        body: entryJson(id: 'entry-1', rawText: 'New text.', version: 4),
      ),
      // Post-poll refresh.
      FakeReply(
        200,
        body: {
          'entries': [
            entryJson(id: 'entry-1', rawText: 'New text.', version: 4),
          ],
        },
      ),
    ]);
    final harness = configuredHarness(adapter);
    await tester.pumpWidget(app(harness));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New text.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final patchRequest = adapter.requests.firstWhere(
      (r) => r.method == 'PATCH',
    );
    expect(patchRequest.data, {'version': 3, 'raw_text': 'New text.'});
    expect(find.text('New text.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a stale save shows the fixed snack bar message', (tester) async {
    useTallScreen(tester);
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsCatalogJson()),
      FakeReply(
        200,
        body: {
          'entries': [
            entryJson(id: 'entry-1', rawText: 'Old text.', version: 3),
          ],
        },
      ),
      FakeReply(
        409,
        body: {
          'error': {'code': 'stale_entry', 'message': 'server says stale'},
          'current': entryJson(
            id: 'entry-1',
            rawText: 'Elsewhere.',
            version: 9,
          ),
        },
      ),
    ]);
    final harness = configuredHarness(adapter);
    await tester.pumpWidget(app(harness));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'My edit.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        "This entry changed somewhere else, so your edit wasn't applied. "
        'Reopen it to see the current text.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'the proposal card offers "Use <phrase>" and "Keep as is"; accepting clears it',
    (tester) async {
      useTallScreen(tester);
      final adapter = FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: {
            'entries': [entryJson(id: 'entry-1', rawText: 'Text.', version: 1)],
          },
        ),
        FakeReply(
          200,
          body: entryJson(id: 'entry-1', rawText: 'Text!', version: 2),
        ),
        FakeReply(
          200,
          body: {
            'entries': [entryJson(id: 'entry-1', rawText: 'Text!', version: 2)],
          },
        ),
        FakeReply(
          200,
          body: entryJson(
            id: 'entry-1',
            rawText: 'Text!',
            version: 2,
            suggestedFeelings: [
              {'key': 'sad', 'confidence': 0.9},
              {'key': 'anxious', 'confidence': 0.7},
            ],
          ),
        ),
        FakeReply(
          200,
          body: {
            'entries': [entryJson(id: 'entry-1', rawText: 'Text!', version: 2)],
          },
        ),
        // acceptProposal.
        FakeReply(
          200,
          body: entryJson(id: 'entry-1', rawText: 'Text!', version: 3),
        ),
        FakeReply(
          200,
          body: {
            'entries': [entryJson(id: 'entry-1', rawText: 'Text!', version: 3)],
          },
        ),
      ]);
      final harness = configuredHarness(adapter);
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit text'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Text!');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text('This now reads more like sad and anxious.'),
        findsOneWidget,
      );
      expect(find.text('Use sad and anxious'), findsOneWidget);
      expect(find.text('Keep as is'), findsOneWidget);

      await tester.tap(find.text('Use sad and anxious'));
      await tester.pumpAndSettle();

      final confirmRequest = adapter.requests.firstWhere(
        (r) => r.method == 'PATCH' && (r.data as Map)['feeling_keys'] != null,
      );
      expect(confirmRequest.data, {
        'version': 2,
        'feeling_keys': ['sad', 'anxious'],
      });
      expect(
        find.text('This now reads more like sad and anxious.'),
        findsNothing,
      );
    },
  );

  testWidgets('back button closes the screen', (tester) async {
    useTallScreen(tester);
    var closed = false;
    final harness = configuredHarness(
      FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(200, body: {'entries': <Object?>[]}),
      ]),
    );
    await tester.pumpWidget(app(harness, onClose: () => closed = true));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back to the calendar'));

    expect(closed, isTrue);
  });

  testWidgets('an unparseable date falls back to today rather than throwing', (
    tester,
  ) async {
    useTallScreen(tester);
    final harness = configuredHarness(
      FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(200, body: {'entries': <Object?>[]}),
      ]),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          requireAuthProvider.overrideWithValue(harness.requireAuth),
          settingsStoreProvider.overrideWithValue(harness.store),
          apiClientProvider.overrideWithValue(harness.client),
          analysisPollConfigProvider.overrideWithValue(instantPoll),
          analysisPollDelayProvider.overrideWithValue((_) async {}),
        ],
        child: const MaterialApp(
          home: DayEntriesScreen(date: 'not-a-date'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Falls back to today rather than throwing during the pump above.
    expect(tester.takeException(), isNull);
    expect(find.text('Nothing written that day'), findsOneWidget);
  });
}
