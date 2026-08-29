import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/entry/entry_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

void main() {
  const entryId = 'entry-1';
  const entryDate = '2026-08-05';

  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Harness configuredHarness(FakeHttpAdapter adapter) => Harness(
    settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
    adapter: adapter,
  );

  Widget app(
    Harness harness, {
    VoidCallback? onClose,
    VoidCallback? onDeleted,
    VoidCallback? onOpenInsights,
  }) => ProviderScope(
    overrides: [
      requireAuthProvider.overrideWithValue(harness.requireAuth),
      settingsStoreProvider.overrideWithValue(harness.store),
      apiClientProvider.overrideWithValue(harness.client),
    ],
    child: MaterialApp(
      home: EntryDetailScreen(
        entryId: entryId,
        entryDate: entryDate,
        onClose: onClose,
        onDeleted: onDeleted,
        onOpenInsights: onOpenInsights,
      ),
    ),
  );

  List<FakeReply> bootReplies({
    FakeReply? entry,
    FakeReply? insights,
    FakeReply? supportingPatterns,
  }) => [
    FakeReply(200, body: feelingsCatalogJson()),
    entry ?? FakeReply(200, body: entryJson()),
    insights ?? FakeReply(200, body: insightsJson()),
    supportingPatterns ?? FakeReply(200, body: {'echoes': <Object?>[]}),
  ];

  testWidgets(
    'a freeform entry splits its text into paragraphs on blank lines',
    (
      tester,
    ) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter(
          bootReplies(
            entry: FakeReply(
              200,
              body: entryJson(rawText: 'First paragraph.\n\nSecond paragraph.'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      expect(find.text('First paragraph.'), findsOneWidget);
      expect(find.text('Second paragraph.'), findsOneWidget);
    },
  );

  testWidgets('a guided entry shows each question above its own answer', (
    tester,
  ) async {
    useTallScreen(tester);
    final harness = configuredHarness(
      FakeHttpAdapter(
        bootReplies(
          entry: FakeReply(
            200,
            body: entryJson(
              mode: 'guided',
              rawText: '',
              guidedAnswers: [
                {
                  'question_key': 'general',
                  'question_text': 'How was your day?',
                  'answer_text': 'Pretty good.',
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(harness));
    await tester.pumpAndSettle();

    expect(find.text('How was your day?'), findsOneWidget);
    expect(find.text('Pretty good.'), findsOneWidget);
  });

  testWidgets(
    'feelings are stated as "N of maxIntensity", not drawn as a bar',
    (
      tester,
    ) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter(
          bootReplies(
            entry: FakeReply(
              200,
              body: entryJson(
                feelingKeys: const ['happy'],
                feelingIntensities: const {'happy': 3},
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      expect(find.text('Happy'), findsOneWidget);
      expect(find.text('3 of 5'), findsOneWidget);
    },
  );

  group('header', () {
    testWidgets('shows the entry\'s date, time and a Freeform mode chip', (
      tester,
    ) async {
      useTallScreen(tester);
      const createdAt = '2026-08-28T23:11:00Z';
      final harness = configuredHarness(
        FakeHttpAdapter(
          bootReplies(
            entry: FakeReply(
              200,
              body: entryJson(mode: 'freeform', createdAt: createdAt),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      final local = DateTime.parse(createdAt).toLocal();
      final expectedHeader =
          '${DateFormat('EEEE, MMMM d').format(local)} · '
          '${DateFormat.jm().format(local)}';
      expect(find.text(expectedHeader), findsOneWidget);
      expect(find.text('FREEFORM'), findsOneWidget);
    });

    testWidgets('shows a Guided mode chip for a guided entry', (
      tester,
    ) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter(
          bootReplies(
            entry: FakeReply(
              200,
              body: entryJson(
                mode: 'guided',
                rawText: '',
                guidedAnswers: [
                  {
                    'question_key': 'general',
                    'question_text': 'How was your day?',
                    'answer_text': 'Fine.',
                  },
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      expect(find.text('GUIDED'), findsOneWidget);
    });
  });

  group('feeling source', () {
    testWidgets('a confirmed feeling carries a tooltip naming its source', (
      tester,
    ) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter(
          bootReplies(
            entry: FakeReply(
              200,
              body: entryJson(feelingKeys: const ['happy']),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Confirmed'), findsOneWidget);
    });

    testWidgets('a suggested feeling names itself as such', (tester) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter(
          bootReplies(
            entry: FakeReply(
              200,
              body: entryJson(
                feelingKeys: const ['happy'],
                feelingSource: 'suggested',
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Suggested by the app, not yet confirmed'),
        findsOneWidget,
      );
    });

    testWidgets('an overridden feeling names itself as such', (tester) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter(
          bootReplies(
            entry: FakeReply(
              200,
              body: entryJson(
                feelingKeys: const ['happy'],
                feelingSource: 'overridden',
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Chosen in place of what was suggested'),
        findsOneWidget,
      );
    });

    testWidgets(
      'an entry with no recorded source shows a plain chip, no tooltip',
      (tester) async {
        useTallScreen(tester);
        final harness = configuredHarness(
          FakeHttpAdapter(
            bootReplies(
              entry: FakeReply(
                200,
                body: entryJson(
                  feelingKeys: const ['happy'],
                  feelingSource: 'not_a_real_source',
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(app(harness));
        await tester.pumpAndSettle();

        expect(find.text('Happy'), findsOneWidget);
        // No source-marker tooltip -- only the app bar's own (Back/Edit
        // entry/Delete entry) tooltips remain.
        expect(find.byTooltip('Confirmed'), findsNothing);
        expect(
          find.byTooltip('Suggested by the app, not yet confirmed'),
          findsNothing,
        );
        expect(
          find.byTooltip('Chosen in place of what was suggested'),
          findsNothing,
        );
      },
    );
  });

  group('supporting patterns', () {
    testWidgets(
      'lists a matching active pattern under "This entry supports" and '
      'opens Insights on tap',
      (tester) async {
        useTallScreen(tester);
        var opened = false;
        final harness = configuredHarness(
          FakeHttpAdapter(
            bootReplies(
              supportingPatterns: FakeReply(
                200,
                body: {
                  'echoes': <Object?>[echoJson(topic: 'coffee')],
                },
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          app(harness, onOpenInsights: () => opened = true),
        );
        await tester.pumpAndSettle();

        expect(find.text('THIS ENTRY SUPPORTS'), findsOneWidget);
        expect(find.text('Coffee'), findsOneWidget);
        expect(
          find.text('Coffee shows up with feeling anxious often.'),
          findsOneWidget,
        );
        expect(find.text('4 times'), findsOneWidget);

        await tester.tap(find.text('Coffee'));
        await tester.pumpAndSettle();

        expect(opened, isTrue);
      },
    );

    testWidgets('omits the section when no pattern matches', (tester) async {
      useTallScreen(tester);
      final harness = configuredHarness(FakeHttpAdapter(bootReplies()));
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      expect(find.text('THIS ENTRY SUPPORTS'), findsNothing);
    });
  });

  testWidgets(
    'gracefully omits every optional section for an entry with none of them',
    (tester) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter(
          bootReplies(
            entry: FakeReply(
              200,
              body: entryJson(feelingKey: null, rawText: 'Just text.'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      expect(find.text('Just text.'), findsOneWidget);
      expect(find.text('FEELINGS'), findsNothing);
      expect(find.text('THIS ENTRY SUPPORTS'), findsNothing);
      expect(find.textContaining('null'), findsNothing);
    },
  );

  testWidgets('exactly one Edit affordance: the bottom button is gone', (
    tester,
  ) async {
    useTallScreen(tester);
    final harness = configuredHarness(FakeHttpAdapter(bootReplies()));
    await tester.pumpWidget(app(harness));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Edit entry'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('the entry is no longer available after a failed load', (
    tester,
  ) async {
    useTallScreen(tester);
    final harness = configuredHarness(
      FakeHttpAdapter(
        bootReplies(entry: FakeReply(404, body: {'error': 'gone'})),
      ),
    );
    await tester.pumpWidget(app(harness));
    await tester.pumpAndSettle();

    expect(find.text('This entry is no longer available.'), findsOneWidget);
  });

  testWidgets(
    'editing seeds the field, and saving closes the editor and confirms it',
    (
      tester,
    ) async {
      useTallScreen(tester);
      final adapter = FakeHttpAdapter([
        ...bootReplies(
          entry: FakeReply(200, body: entryJson(rawText: 'Old.', version: 1)),
        ),
        FakeReply(200, body: entryJson(rawText: 'New.', version: 2)),
        FakeReply(200, body: {'echoes': <Object?>[]}),
      ]);
      final harness = configuredHarness(adapter);
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit entry'));
      await tester.pumpAndSettle();
      expect(find.text('Old.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'New.');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Entry saved'), findsOneWidget);
      expect(find.text('New.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      final patchRequest = adapter.requests.firstWhere(
        (r) => r.method == 'PATCH',
      );
      expect((patchRequest.data as Map)['raw_text'], 'New.');
    },
  );

  testWidgets('back in the editor leaves only the editor, not the entry', (
    tester,
  ) async {
    useTallScreen(tester);
    final harness = configuredHarness(
      FakeHttpAdapter(
        bootReplies(
          entry: FakeReply(200, body: entryJson(rawText: 'Stored.')),
        ),
      ),
    );
    var closed = false;
    await tester.pumpWidget(app(harness, onClose: () => closed = true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit entry'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Stop editing'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop editing'));
    await tester.pumpAndSettle();

    expect(closed, isFalse);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Stored.'), findsOneWidget);
  });

  testWidgets('back outside the editor closes the screen', (tester) async {
    useTallScreen(tester);
    final harness = configuredHarness(
      FakeHttpAdapter(bootReplies(entry: FakeReply(200, body: entryJson()))),
    );
    var closed = false;
    await tester.pumpWidget(app(harness, onClose: () => closed = true));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));

    expect(closed, isTrue);
  });

  group('delete', () {
    testWidgets('asks first, and cancelling deletes nothing', (tester) async {
      useTallScreen(tester);
      final adapter = FakeHttpAdapter(
        bootReplies(entry: FakeReply(200, body: entryJson())),
      );
      final harness = configuredHarness(adapter);
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete entry'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this entry?'), findsOneWidget);
      expect(find.text("This can't be undone."), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(adapter.requests.any((r) => r.method == 'DELETE'), isFalse);
    });

    testWidgets('confirming deletes and notifies the caller', (tester) async {
      useTallScreen(tester);
      final adapter = FakeHttpAdapter([
        ...bootReplies(entry: FakeReply(200, body: entryJson())),
        FakeReply(204),
      ]);
      final harness = configuredHarness(adapter);
      var deleted = false;
      await tester.pumpWidget(app(harness, onDeleted: () => deleted = true));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });
  });

  group('conflict handling -- the delicate part', () {
    Map<String, Object?> staleBody({
      String rawText = "Someone else's edit.",
      int version = 9,
    }) => {
      'error': {'code': 'stale_entry', 'message': 'stale'},
      'current': entryJson(rawText: rawText, version: version),
    };

    Future<void> triggerStaleSave(
      WidgetTester tester,
      FakeHttpAdapter adapter,
      Harness harness,
    ) async {
      await tester.pumpWidget(app(harness));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit entry'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'My unsaved edit.');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
    }

    testWidgets('a stale save surfaces the panel with both texts intact', (
      tester,
    ) async {
      useTallScreen(tester);
      final adapter = FakeHttpAdapter([
        ...bootReplies(
          entry: FakeReply(
            200,
            body: entryJson(rawText: 'Original.', version: 1),
          ),
        ),
        FakeReply(409, body: staleBody()),
      ]);
      await triggerStaleSave(tester, adapter, configuredHarness(adapter));

      expect(find.text('This entry changed elsewhere'), findsOneWidget);
      expect(find.text('My unsaved edit.'), findsOneWidget);
      expect(find.text("Someone else's edit."), findsOneWidget);
      expect(find.text('Keep mine (overwrite)'), findsOneWidget);
      expect(find.text('Keep editing mine'), findsOneWidget);
      expect(find.text('Discard mine and use theirs'), findsOneWidget);
    });

    testWidgets(
      '"Keep mine" retries against the conflict\'s version and succeeds',
      (
        tester,
      ) async {
        useTallScreen(tester);
        final adapter = FakeHttpAdapter([
          ...bootReplies(
            entry: FakeReply(
              200,
              body: entryJson(rawText: 'Original.', version: 1),
            ),
          ),
          FakeReply(409, body: staleBody(version: 9)),
          FakeReply(
            200,
            body: entryJson(rawText: 'My unsaved edit.', version: 10),
          ),
          FakeReply(200, body: {'echoes': <Object?>[]}),
        ]);
        await triggerStaleSave(tester, adapter, configuredHarness(adapter));

        await tester.tap(find.text('Keep mine (overwrite)'));
        await tester.pumpAndSettle();

        expect(find.text('This entry changed elsewhere'), findsNothing);
        expect(find.text('My unsaved edit.'), findsOneWidget);
        final retryRequest = adapter.requests
            .where((r) => r.method == 'PATCH')
            .last;
        expect((retryRequest.data as Map)['version'], 9);
      },
    );

    testWidgets(
      '"Keep editing mine" returns to the editor with the draft over the current entry',
      (
        tester,
      ) async {
        useTallScreen(tester);
        final adapter = FakeHttpAdapter([
          ...bootReplies(
            entry: FakeReply(
              200,
              body: entryJson(rawText: 'Original.', version: 1),
            ),
          ),
          FakeReply(
            409,
            body: staleBody(rawText: 'Current on server.', version: 9),
          ),
        ]);
        await triggerStaleSave(tester, adapter, configuredHarness(adapter));

        await tester.tap(find.text('Keep editing mine'));
        await tester.pumpAndSettle();

        expect(find.text('This entry changed elsewhere'), findsNothing);
        // Back in the editor, with the user's own words -- not the server's.
        expect(find.byType(TextField), findsWidgets);
        expect(find.text('My unsaved edit.'), findsOneWidget);
      },
    );

    testWidgets('"Discard mine" adopts the server copy', (tester) async {
      useTallScreen(tester);
      final adapter = FakeHttpAdapter([
        ...bootReplies(
          entry: FakeReply(
            200,
            body: entryJson(rawText: 'Original.', version: 1),
          ),
        ),
        FakeReply(
          409,
          body: staleBody(rawText: 'Current on server.', version: 9),
        ),
      ]);
      await triggerStaleSave(tester, adapter, configuredHarness(adapter));

      await tester.tap(find.text('Discard mine and use theirs'));
      await tester.pumpAndSettle();

      expect(find.text('This entry changed elsewhere'), findsNothing);
      expect(find.text('Current on server.'), findsOneWidget);
      expect(find.text('My unsaved edit.'), findsNothing);
    });

    testWidgets('a stale delete shows the panel rather than deleting', (
      tester,
    ) async {
      useTallScreen(tester);
      final adapter = FakeHttpAdapter([
        ...bootReplies(
          entry: FakeReply(
            200,
            body: entryJson(rawText: 'Original.', version: 1),
          ),
        ),
        FakeReply(409, body: staleBody()),
      ]);
      final harness = configuredHarness(adapter);
      var deleted = false;
      await tester.pumpWidget(app(harness, onDeleted: () => deleted = true));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(deleted, isFalse);
      expect(find.text('This entry changed elsewhere'), findsOneWidget);
    });
  });

  testWidgets('an unparseable entryDate never throws', (tester) async {
    useTallScreen(tester);
    final harness = configuredHarness(
      FakeHttpAdapter(bootReplies(entry: FakeReply(200, body: entryJson()))),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          requireAuthProvider.overrideWithValue(harness.requireAuth),
          settingsStoreProvider.overrideWithValue(harness.store),
          apiClientProvider.overrideWithValue(harness.client),
        ],
        child: const MaterialApp(
          home: EntryDetailScreen(entryId: entryId, entryDate: 'not-a-date'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
