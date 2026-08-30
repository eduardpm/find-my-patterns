import 'dart:async';

import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/features/calendar/day_entries_controller.dart';
import 'package:find_my_patterns/features/calendar/day_entries_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

  Widget app(
    Harness harness, {
    VoidCallback? onClose,
    ValueChanged<Entry>? onOpenEntry,
    DateTime? now,
  }) => ProviderScope(
    overrides: [
      requireAuthProvider.overrideWithValue(harness.requireAuth),
      settingsStoreProvider.overrideWithValue(harness.store),
      apiClientProvider.overrideWithValue(harness.client),
      analysisPollConfigProvider.overrideWithValue(instantPoll),
      analysisPollDelayProvider.overrideWithValue((_) async {}),
      if (now != null) dayEntriesNowProvider.overrideWithValue(now),
    ],
    child: MaterialApp(
      home: DayEntriesScreen(
        date: '$date',
        onClose: onClose,
        onOpenEntry: onOpenEntry,
      ),
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

  testWidgets(
    'an empty day offers "Write about this day", which opens the composer '
    'for that day (#36)',
    (tester) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          FakeReply(200, body: {'entries': <Object?>[]}),
        ]),
      );
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => DayEntriesScreen(date: '$date'),
          ),
          GoRoute(
            path: '/compose',
            builder: (context, state) => Scaffold(
              body: Text(
                'compose destination: ${state.uri.queryParameters['date']}',
              ),
            ),
          ),
        ],
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
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing written that day'), findsOneWidget);

      await tester.tap(find.text('Write about this day'));
      await tester.pumpAndSettle();

      expect(
        find.text('compose destination: $date'),
        findsOneWidget,
      );
    },
  );

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

    // #150 task 1: the accessible name comes from the semantics tree's
    // `label`, not `IconButton`'s own `tooltip` field.
    expect(find.bySemanticsLabel('Back to the calendar'), findsOneWidget);

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

  testWidgets('a long entry is truncated to six lines with an ellipsis', (
    tester,
  ) async {
    useTallScreen(tester);
    final longText = List.generate(10, (i) => 'Line $i').join('\n');
    final harness = configuredHarness(
      FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: {
            'entries': [entryJson(id: 'entry-1', rawText: longText)],
          },
        ),
      ]),
    );
    await tester.pumpWidget(app(harness));
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.text(longText));
    expect(text.maxLines, 6);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('tapping an entry opens it in the entry-detail screen', (
    tester,
  ) async {
    useTallScreen(tester);
    Entry? opened;
    final harness = configuredHarness(
      FakeHttpAdapter([
        FakeReply(200, body: feelingsCatalogJson()),
        FakeReply(
          200,
          body: {
            'entries': [entryJson(id: 'entry-1', rawText: 'Tap me.')],
          },
        ),
      ]),
    );
    await tester.pumpWidget(
      app(harness, onOpenEntry: (entry) => opened = entry),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tap me.'));

    expect(opened?.id, 'entry-1');
  });

  group('paging between days', () {
    // A clock pinned well after `date`, so the swipe test's forward step
    // never runs into the today ceiling the next group is testing.
    final midMonth = DateTime.utc(2026, 8, 20, 12);

    /// However many requests a page turn ends up needing, every one gets
    /// the same empty-day reply after the shared feelings catalog -- these
    /// tests are about which day is on screen, not what is in it, so which
    /// date a particular request was for does not matter.
    FakeHttpAdapter emptyDayAdapter() => FakeHttpAdapter([
      FakeReply(200, body: feelingsCatalogJson()),
      for (var i = 0; i < 20; i++)
        FakeReply(200, body: {'entries': <Object?>[]}),
    ]);

    testWidgets('a leftward swipe moves to the next day', (tester) async {
      useTallScreen(tester);
      final harness = configuredHarness(emptyDayAdapter());
      await tester.pumpWidget(app(harness, now: midMonth));
      await tester.pumpAndSettle();
      expect(find.text('WEDNESDAY, AUGUST 5'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.text('WEDNESDAY, AUGUST 5'), findsNothing);
      expect(find.text('THURSDAY, AUGUST 6'), findsOneWidget);
    });

    testWidgets('a rightward swipe moves to the previous day', (
      tester,
    ) async {
      useTallScreen(tester);
      final harness = configuredHarness(emptyDayAdapter());
      await tester.pumpWidget(app(harness, now: midMonth));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(600, 0));
      await tester.pumpAndSettle();

      expect(find.text('TUESDAY, AUGUST 4'), findsOneWidget);
    });

    testWidgets('the next-day chevron steps forward the same way a swipe '
        'does', (tester) async {
      useTallScreen(tester);
      final harness = configuredHarness(emptyDayAdapter());
      await tester.pumpWidget(app(harness, now: midMonth));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Next day'));
      await tester.pumpAndSettle();

      expect(find.text('THURSDAY, AUGUST 6'), findsOneWidget);
    });
  });

  group('the forward swipe ceiling', () {
    // `date` itself is "today" on this clock, so the forward direction has
    // nowhere left to go.
    final onDate = DateTime.utc(2026, 8, 5, 12);

    testWidgets('the next-day chevron is disabled on today', (tester) async {
      final handle = tester.ensureSemantics();
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          FakeReply(200, body: {'entries': <Object?>[]}),
        ]),
      );
      await tester.pumpWidget(app(harness, now: onDate));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Next day')),
        matchesSemantics(
          label: 'Next day',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('a leftward swipe on today does not move forward', (
      tester,
    ) async {
      useTallScreen(tester);
      final harness = configuredHarness(
        FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          FakeReply(200, body: {'entries': <Object?>[]}),
        ]),
      );
      await tester.pumpWidget(app(harness, now: onDate));
      await tester.pumpAndSettle();
      expect(find.text('WEDNESDAY, AUGUST 5'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.text('WEDNESDAY, AUGUST 5'), findsOneWidget);
    });
  });

  group('dynamic type at the required matrix (#155)', () {
    // The structures the orchestrator flagged as worth probing
    // (`day_entries_screen.dart` :177 the page `Stack`, :375/:425/:447 the
    // analysing-notice and proposal-card `Row`s, :581/:591/:609/:637 the
    // editing card's rows, :476 the feeling `_Dot`, :574 the editing
    // card's `DecoratedBox`). Every cell is measured, not assumed --
    // including the ones that render clean, so the zeroes are recorded as
    // evidence the sweep actually happened.
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
          'the entry list renders with no overflow at '
          '${width.toInt()}dp / ${scale}x',
          (tester) async {
            final harness = configuredHarness(
              FakeHttpAdapter([
                FakeReply(200, body: feelingsCatalogJson()),
                FakeReply(
                  200,
                  body: {
                    'entries': [
                      entryJson(
                        id: 'entry-1',
                        rawText: 'A fairly ordinary Wednesday, all told.',
                        feelingKeys: const ['happy', 'sad', 'anxious'],
                      ),
                    ],
                  },
                ),
              ]),
            );
            await pumpAtScale(tester, app(harness), width: width, scale: scale);

            expect(tester.takeException(), isNull);
            expect(find.text('WEDNESDAY, AUGUST 5'), findsOneWidget);
            expect(find.text('1 entry'), findsOneWidget);
            expect(find.text('Happy'), findsOneWidget);
            expect(find.text('Anxious'), findsOneWidget);
          },
        );
      }
    }

    testWidgets(
      'the re-analysing notice renders with no overflow at 320dp/2x',
      (tester) async {
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
        ]);
        final harness = configuredHarness(adapter);
        // `analysisPollDelayProvider` overridden with a `Completer` that is
        // never completed, so the poll loop blocks forever on its first
        // `await delay(...)` right after `isAnalysing: true` is set --
        // deterministic, unlike racing a single `pump()` against the
        // default fakes, which resolve the whole save-refresh-poll chain
        // as microtasks before a single frame ever gets a chance to catch
        // the notice on screen.
        final delayCompleter = Completer<void>();
        addTearDown(delayCompleter.complete);
        await pumpAtScale(
          tester,
          ProviderScope(
            overrides: [
              requireAuthProvider.overrideWithValue(harness.requireAuth),
              settingsStoreProvider.overrideWithValue(harness.store),
              apiClientProvider.overrideWithValue(harness.client),
              analysisPollConfigProvider.overrideWithValue(instantPoll),
              analysisPollDelayProvider.overrideWithValue(
                (_) => delayCompleter.future,
              ),
            ],
            child: MaterialApp(home: DayEntriesScreen(date: '$date')),
          ),
          width: 320,
          scale: 2,
        );

        await tester.tap(find.text('Edit text'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'New text.');
        await tester.tap(find.text('Save'));
        // Not `pumpAndSettle`: the notice's own `CircularProgressIndicator`
        // schedules a new frame forever while `isAnalysing` stays true (by
        // design here, via the un-completed `delayCompleter`), so
        // `pumpAndSettle` would never see an idle frame and time out.
        // `saveEdit` crosses two awaited network round trips (the `PATCH`,
        // then `refresh()`) before it blocks on the poll delay, each a
        // fresh microtask boundary a single frame does not necessarily
        // drain -- so this pumps a bounded number of plain frames rather
        // than guessing the exact count.
        for (
          var i = 0;
          i < 10 && find.text('Re-reading that entry…').evaluate().isEmpty;
          i++
        ) {
          // A duration, not a bare `pump()`: `saveEdit` waits on
          // `entriesApiProvider`'s own async gap, which needs the fake
          // clock to actually advance to resolve -- a zero-duration
          // `pump()` never fires it, and the loop spins without
          // progressing.
          await tester.pump(const Duration(milliseconds: 5));
        }

        expect(tester.takeException(), isNull);
        expect(find.text('Re-reading that entry…'), findsOneWidget);
      },
    );

    testWidgets(
      'the feeling-proposal card and its "Use <phrase>" button render with '
      'no overflow at 320dp/2x',
      (tester) async {
        final adapter = FakeHttpAdapter([
          FakeReply(200, body: feelingsCatalogJson()),
          FakeReply(
            200,
            body: {
              'entries': [
                entryJson(id: 'entry-1', rawText: 'Text.', version: 1),
              ],
            },
          ),
          FakeReply(
            200,
            body: entryJson(id: 'entry-1', rawText: 'Text!', version: 2),
          ),
          FakeReply(
            200,
            body: {
              'entries': [
                entryJson(id: 'entry-1', rawText: 'Text!', version: 2),
              ],
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
              'entries': [
                entryJson(id: 'entry-1', rawText: 'Text!', version: 2),
              ],
            },
          ),
        ]);
        final harness = configuredHarness(adapter);
        await pumpAtScale(tester, app(harness), width: 320, scale: 2);
        await tester.tap(find.text('Edit text'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Text!');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text('This now reads more like sad and anxious.'),
          findsOneWidget,
        );
        expect(find.text('Use sad and anxious'), findsOneWidget);
        expect(find.text('Keep as is'), findsOneWidget);
      },
    );

    testWidgets(
      'the editing card (feeling row, text field, Save/Cancel) renders '
      'with no overflow at 320dp/2x',
      (tester) async {
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: feelingsCatalogJson()),
            FakeReply(
              200,
              body: {
                'entries': [
                  entryJson(
                    id: 'entry-1',
                    rawText: 'Old text.',
                    feelingKeys: const ['happy', 'sad', 'anxious'],
                  ),
                ],
              },
            ),
          ]),
        );
        await pumpAtScale(tester, app(harness), width: 320, scale: 2);
        await tester.tap(find.text('Edit text'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Happy'), findsOneWidget);
        expect(find.text('Anxious'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
      },
    );

    testWidgets(
      'the back button and both day-step chevrons stay at least 48dp at '
      '320dp/2x',
      (tester) async {
        final handle = tester.ensureSemantics();
        final harness = configuredHarness(
          FakeHttpAdapter([
            FakeReply(200, body: feelingsCatalogJson()),
            FakeReply(200, body: {'entries': <Object?>[]}),
          ]),
        );
        await pumpAtScale(tester, app(harness), width: 320, scale: 2);

        expect(tester.takeException(), isNull);
        final backSize = tester.getSize(
          find.bySemanticsLabel('Back to the calendar'),
        );
        expect(backSize.width, greaterThanOrEqualTo(48));
        expect(backSize.height, greaterThanOrEqualTo(48));
        final previousSize = tester.getSize(
          find.bySemanticsLabel('Previous day'),
        );
        expect(previousSize.width, greaterThanOrEqualTo(48));
        expect(previousSize.height, greaterThanOrEqualTo(48));
        handle.dispose();
      },
    );
  });
}
