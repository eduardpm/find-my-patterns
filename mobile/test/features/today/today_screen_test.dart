import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/core/widgets/journal.dart';
import 'package:find_my_patterns/core/widgets/journal_fab_clearance.dart';
import 'package:find_my_patterns/features/today/entry_card.dart';
import 'package:find_my_patterns/features/today/today_controller.dart';
import 'package:find_my_patterns/features/today/today_screen.dart';
import 'package:find_my_patterns/features/today/writing_streak_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../support/fake_backdate_nudge_store.dart';
import '../../support/fake_http.dart';
import '../../support/harness.dart';
import '../experiments/json_fixtures.dart'
    show experimentJson, noActiveExperimentErrorJson;
import 'json_fixtures.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 8, 28, 10);
  final today = CalendarDate.today(now: fixedNow);
  final feelingsReply = FakeReply(200, body: feelingsCatalogJson());

  /// `GET /experiments/active`'s reply when nothing is running (R-3b) --
  /// the common case every test in this file that is not itself about the
  /// experiment banner scripts as [loadReplies]' fourth reply.
  FakeReply noActiveExperimentReply() =>
      FakeReply(404, body: noActiveExperimentErrorJson());

  /// One `refresh`'s worth of replies while showing *today*, once the
  /// feelings catalog is cached: entries, the monthly summary, the
  /// writing-streak series (#40), then the active experiment (R-3b) -- see
  /// `today_controller_test.dart`'s identically-named helper for why a
  /// load of a past day needs [pastDayReplies] instead.
  List<FakeReply> loadReplies({
    List<Map<String, Object?>> entries = const [],
    List<Map<String, Object?>> days = const [],
    List<CalendarDate> streakDays = const [],
    FakeReply? activeExperimentReply,
  }) => [
    FakeReply(200, body: entriesJson(entries)),
    FakeReply(200, body: monthlySummaryJson(days: days)),
    FakeReply(200, body: seriesJson(days: streakDays)),
    activeExperimentReply ?? noActiveExperimentReply(),
  ];

  /// One `refresh`'s worth of replies while showing a day other than today:
  /// no writing-streak series call off today (#40).
  List<FakeReply> pastDayReplies({
    List<Map<String, Object?>> entries = const [],
    List<Map<String, Object?>> days = const [],
  }) => [
    FakeReply(200, body: entriesJson(entries)),
    FakeReply(200, body: monthlySummaryJson(days: days)),
  ];

  Widget buildTestable({
    required List<FakeReply> replies,
    VoidCallback? onNewEntry,
    ValueChanged<Entry>? onOpenEntry,
    ValueChanged<String>? onOpenExperiment,
    FakeBackdateNudgeStore? nudgeStore,
  }) {
    final harness = Harness(
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
      adapter: FakeHttpAdapter([feelingsReply, ...replies]),
    );
    return ProviderScope(
      overrides: [
        requireAuthProvider.overrideWithValue(harness.requireAuth),
        settingsStoreProvider.overrideWithValue(harness.store),
        apiClientProvider.overrideWithValue(harness.client),
        // Dismissed by default: the backdate nudge (#36) is its own
        // concern, tested in its own group below, and every test in this
        // file that predates it built its expectations -- including some
        // that tap a widget positioned by how tall the page is -- around a
        // layout that never had to make room for it. A test that wants to
        // see the card passes its own non-dismissed [nudgeStore].
        backdateNudgeStoreProvider.overrideWithValue(
          nudgeStore ?? FakeBackdateNudgeStore(dismissed: true),
        ),
        todayControllerProvider.overrideWith(
          () => TodayController(now: () => fixedNow, delay: (_) async {}),
        ),
      ],
      child: MaterialApp(
        home: TodayScreen(
          onNewEntry: onNewEntry,
          onOpenEntry: onOpenEntry,
          onOpenExperiment: onOpenExperiment,
        ),
      ),
    );
  }

  /// Boots the screen behind a real (throwaway) [GoRouter], the same
  /// pattern `settings_screen_test.dart`'s "the topics card opens the
  /// topics route" test uses -- only the nudge's "Write about yesterday"
  /// tap needs this, since it navigates through `context.push` rather than
  /// through [TodayScreen.onNewEntry].
  Widget buildRoutedTestable({
    required List<FakeReply> replies,
    FakeBackdateNudgeStore? nudgeStore,
  }) {
    final harness = Harness(
      settings: const AppSettings(backend: BackendAddress(host: '10.0.2.2')),
      adapter: FakeHttpAdapter([feelingsReply, ...replies]),
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const TodayScreen()),
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
    return ProviderScope(
      overrides: [
        requireAuthProvider.overrideWithValue(harness.requireAuth),
        settingsStoreProvider.overrideWithValue(harness.store),
        apiClientProvider.overrideWithValue(harness.client),
        backdateNudgeStoreProvider.overrideWithValue(
          nudgeStore ?? FakeBackdateNudgeStore(),
        ),
        todayControllerProvider.overrideWith(
          () => TodayController(now: () => fixedNow, delay: (_) async {}),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  group('header', () {
    testWidgets('reads "Today" with the date spelled out as the eyebrow', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(buildTestable(replies: loadReplies()));
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      // The eyebrow's own semantics node merges with its adjacent title
      // sibling (neither sets `container: true`), so this checks the
      // combined label contains the spelled-out date rather than matching
      // it exactly.
      expect(
        tester.getSemantics(find.byType(Eyebrow)).label,
        contains(DateFormat('EEEE, MMMM d').format(today.toDateTime())),
      );
      handle.dispose();
    });

    testWidgets('reads "Yesterday" after stepping back one day', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestable(replies: [...loadReplies(), ...pastDayReplies()]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Previous day'));
      await tester.pumpAndSettle();

      expect(find.text('Yesterday'), findsOneWidget);
    });

    testWidgets('the Today button only appears once the reader has moved '
        'off today', (tester) async {
      await tester.pumpWidget(
        buildTestable(replies: [...loadReplies(), ...pastDayReplies()]),
      );
      await tester.pumpAndSettle();
      // Only the title reads "Today" -- no button by that name yet.
      expect(find.text('Today'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Today'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Previous day'));
      await tester.pumpAndSettle();

      // Now the title reads "Yesterday" and the Today button has appeared.
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('tapping Today returns from a past day to today', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestable(
          replies: [...loadReplies(), ...pastDayReplies(), ...loadReplies()],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Previous day'));
      await tester.pumpAndSettle();
      expect(find.text('Yesterday'), findsOneWidget);

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      // Back on today: the title reads "Today" and the button is gone
      // again, since it only appears when it would do something.
      expect(find.text('Yesterday'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Today'), findsNothing);
    });
  });

  group('active experiment banner (R-3b)', () {
    testWidgets('shows once an experiment is active, and opens it on tap', (
      tester,
    ) async {
      String? openedId;
      await tester.pumpWidget(
        buildTestable(
          replies: loadReplies(
            activeExperimentReply: FakeReply(
              200,
              body: experimentJson(
                id: 'experiment-9',
                patternTopic: 'walking',
                startDate: today.toString(),
                endDate: today.addDays(6).toString(),
              ),
            ),
          ),
          onOpenExperiment: (id) => openedId = id,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Experiment: more walking · day 1 of 7'),
        findsOneWidget,
      );

      await tester.tap(find.text('Experiment: more walking · day 1 of 7'));

      expect(openedId, 'experiment-9');
    });

    testWidgets('is absent while nothing is running', (tester) async {
      await tester.pumpWidget(buildTestable(replies: loadReplies()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Experiment:'), findsNothing);
    });

    testWidgets('is absent while paging through a past day', (tester) async {
      await tester.pumpWidget(
        buildTestable(
          replies: [
            ...loadReplies(
              activeExperimentReply: FakeReply(
                200,
                body: experimentJson(patternTopic: 'walking'),
              ),
            ),
            ...pastDayReplies(),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Experiment:'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      expect(find.textContaining('Experiment:'), findsNothing);
    });
  });

  group('writing streak (#40)', () {
    testWidgets('shows the streak once the series call reports enough '
        'consecutive days', (tester) async {
      final yesterday = today.addDays(-1);
      await tester.pumpWidget(
        buildTestable(
          replies: loadReplies(streakDays: [today, yesterday]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WritingStreakLine), findsOneWidget);
      expect(find.text('2 days writing'), findsOneWidget);
    });

    testWidgets('stays hidden for a one-day streak', (tester) async {
      await tester.pumpWidget(
        buildTestable(replies: loadReplies(streakDays: [today])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WritingStreakLine), findsNothing);
    });

    testWidgets(
      'still shows when today is empty but yesterday was streaking -- not '
      'broken until the day is over',
      (tester) async {
        final yesterday = today.addDays(-1);
        await tester.pumpWidget(
          buildTestable(
            replies: loadReplies(
              // No entry for today itself; the series call still names
              // yesterday and the day before as written.
              streakDays: [yesterday, yesterday.addDays(-1)],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('2 days writing'), findsOneWidget);
      },
    );

    testWidgets('is hidden while paging through a past day', (tester) async {
      await tester.pumpWidget(
        buildTestable(
          replies: [
            ...loadReplies(streakDays: [today, today.addDays(-1)]),
            ...pastDayReplies(),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WritingStreakLine), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Previous day'));
      await tester.pumpAndSettle();

      expect(find.byType(WritingStreakLine), findsNothing);
    });
  });

  group('backdate nudge (#36)', () {
    const nudgeTitle = 'How was yesterday?';

    testWidgets(
      'shows once loaded, on today, under 7 total entries, and not '
      'dismissed',
      (tester) async {
        await tester.pumpWidget(
          buildTestable(
            replies: loadReplies(streakDays: [today]),
            nudgeStore: FakeBackdateNudgeStore(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(nudgeTitle), findsOneWidget);
        expect(
          find.text(
            'Adding a day or two helps your patterns appear sooner.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('stays hidden once the diary reaches 7 total entries', (
      tester,
    ) async {
      final sevenDays = [for (var i = 0; i < 7; i++) today.addDays(-i)];
      await tester.pumpWidget(
        buildTestable(
          replies: loadReplies(streakDays: sevenDays),
          nudgeStore: FakeBackdateNudgeStore(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(nudgeTitle), findsNothing);
    });

    testWidgets('stays hidden once already dismissed on this device', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestable(
          replies: loadReplies(streakDays: [today]),
          nudgeStore: FakeBackdateNudgeStore(dismissed: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(nudgeTitle), findsNothing);
    });

    testWidgets('stays hidden while paging through a past day', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestable(
          replies: [
            ...loadReplies(streakDays: [today]),
            ...pastDayReplies(),
          ],
          nudgeStore: FakeBackdateNudgeStore(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(nudgeTitle), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Previous day'));
      await tester.pumpAndSettle();

      expect(find.text(nudgeTitle), findsNothing);
    });

    testWidgets(
      'dismissing hides the card immediately and persists through the '
      'store',
      (tester) async {
        final store = FakeBackdateNudgeStore();
        await tester.pumpWidget(
          buildTestable(
            replies: loadReplies(streakDays: [today]),
            nudgeStore: store,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(nudgeTitle), findsOneWidget);

        // #150 task 1: the accessible name comes from the semantics
        // tree's `label`, not `IconButton`'s own `tooltip` field -- see
        // `pattern_echo_panel.dart`'s dismiss button for the same
        // distinction. #150 task 4: this "×" used to set `constraints:
        // const BoxConstraints()` with no minimum at all, shrinking well
        // under the platform's 44dp floor.
        expect(find.bySemanticsLabel('Dismiss'), findsOneWidget);
        final dismissSize = tester.getSize(find.byTooltip('Dismiss'));
        expect(dismissSize.width, greaterThanOrEqualTo(44));
        expect(dismissSize.height, greaterThanOrEqualTo(44));

        await tester.tap(find.byTooltip('Dismiss'));
        await tester.pumpAndSettle();

        expect(find.text(nudgeTitle), findsNothing);
        expect(store.dismissCount, 1);
        expect(await store.isDismissed(), isTrue);
      },
    );

    testWidgets(
      'tapping "Write about yesterday" opens the composer for yesterday',
      (tester) async {
        await tester.pumpWidget(
          buildRoutedTestable(replies: loadReplies(streakDays: [today])),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Write about yesterday'));
        await tester.pumpAndSettle();

        expect(
          find.text('compose destination: ${today.addDays(-1)}'),
          findsOneWidget,
        );
      },
    );
  });

  group('day stepper', () {
    testWidgets('the forward step is disabled on today', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(buildTestable(replies: loadReplies()));
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

    testWidgets('the back step moves to the previous day', (tester) async {
      await tester.pumpWidget(
        buildTestable(replies: [...loadReplies(), ...pastDayReplies()]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Previous day'));
      await tester.pumpAndSettle();

      expect(find.text('Yesterday'), findsOneWidget);
    });

    testWidgets(
      'the forward step re-enables after stepping back a day, and tapping '
      'it returns to today',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          buildTestable(
            replies: [...loadReplies(), ...pastDayReplies(), ...loadReplies()],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.bySemanticsLabel('Previous day'));
        await tester.pumpAndSettle();
        expect(find.text('Yesterday'), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Next day')),
          matchesSemantics(
            label: 'Next day',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );

        // The re-enabled button also actually navigates on a tap -- not
        // just visually distinct, genuinely live again.
        await tester.tap(find.bySemanticsLabel('Next day'));
        await tester.pumpAndSettle();

        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Yesterday'), findsNothing);
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
      },
    );
  });

  group('empty state', () {
    testWidgets('today: an inviting message with a write action', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestable(replies: loadReplies()));
      await tester.pumpAndSettle();

      expect(find.text('Nothing yet today'), findsOneWidget);
      expect(
        find.text('Whatever just happened is worth a line. A sentence counts.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ElevatedButton, 'Write an entry'),
        findsOneWidget,
      );
    });

    testWidgets('a past day: no write action', (tester) async {
      await tester.pumpWidget(
        buildTestable(replies: [...loadReplies(), ...pastDayReplies()]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Previous day'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing was written'), findsOneWidget);
      expect(
        find.text(
          'This day has no entries. Days you did write are marked on the '
          'calendar.',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ElevatedButton, 'Write an entry'),
        findsNothing,
      );
    });
  });

  group('loading', () {
    testWidgets('shows a spinner until the first load finishes', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestable(replies: loadReplies()));
      // Before any pump settles the async load, the spinner is showing --
      // gated on hasLoaded rather than on the entry list being empty.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('entries', () {
    testWidgets('an entry card shows its feelings and text, and opens on '
        'tap', (tester) async {
      Entry? opened;
      await tester.pumpWidget(
        buildTestable(
          replies: loadReplies(
            entries: [entryJson(id: 'e1', rawText: 'A long day at work.')],
          ),
          onOpenEntry: (entry) => opened = entry,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('A long day at work.'), findsOneWidget);
      // "Happy" also appears in the day summary card above the entry list,
      // which reads the same feeling off the same entry — so this looks
      // for it inside the entry card specifically.
      expect(
        find.descendant(
          of: find.byType(EntryCard),
          matching: find.text('Happy'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('A long day at work.'));

      expect(opened?.id, 'e1');
    });
  });

  group('the FAB', () {
    testWidgets('reads "Write an entry" on today and calls onNewEntry', (
      tester,
    ) async {
      var pressed = false;
      await tester.pumpWidget(
        buildTestable(
          replies: loadReplies(),
          onNewEntry: () => pressed = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Write an entry'),
      );

      expect(pressed, isTrue);
    });

    testWidgets('reads "Write for today" on a past day, and returns to '
        'today before calling onNewEntry', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        buildTestable(
          replies: [...loadReplies(), ...pastDayReplies(), ...loadReplies()],
          onNewEntry: () => pressed = true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Previous day'));
      await tester.pumpAndSettle();
      expect(find.text('Yesterday'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Write for today'),
      );
      await tester.pumpAndSettle();

      expect(pressed, isTrue);
      expect(find.text('Today'), findsOneWidget);
    });
  });

  group('edge-to-edge insets (#10)', () {
    /// Enough entries, each with enough text, that the list is taller than
    /// even a generously-sized test viewport -- so "scroll to the end" in
    /// the tests below is a real scroll past real content, not a no-op on
    /// a list that already fit inside the frame.
    List<Map<String, Object?>> manyEntries() => [
      for (var i = 0; i < 12; i++)
        entryJson(
          id: 'entry-$i',
          rawText:
              'Entry number $i, written with enough words that its card '
              'takes up a couple of lines rather than one, the way a real '
              'diary entry does.',
          createdAt: '2026-08-28T09:${i.toString().padLeft(2, '0')}:00',
        ),
    ];

    /// Scrolls the screen's one [Scrollable] all the way to its true end.
    ///
    /// A single `jumpTo(maxScrollExtent)` is not enough here: this test's
    /// entries deliberately vary in height (see [manyEntries]), so
    /// [ScrollPosition.maxScrollExtent] is only an estimate until every
    /// item between here and the bottom has actually been laid out --
    /// jumping to today's estimate can land short, which then realizes a
    /// few more items and revises the estimate upward. Re-reading and
    /// re-jumping until the estimate stops moving is what actually reaches
    /// the position the acceptance criterion ("scrolled to the very end")
    /// names, rather than a fixed-distance drag or fling that would only
    /// prove the list moved *some* amount. This also leaves `_expandFab`
    /// false -- the collapsed "+" state -- the same way a real reader
    /// scrolling away from the top would.
    Future<void> jumpToEnd(WidgetTester tester) async {
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      var previous = double.negativeInfinity;
      var target = scrollable.position.maxScrollExtent;
      while (target != previous) {
        scrollable.position.jumpTo(target);
        await tester.pump();
        previous = target;
        target = scrollable.position.maxScrollExtent;
      }
    }

    for (final (label, size, topInset, bottomInset) in [
      ('portrait, gesture-nav insets', const Size(480, 900), 40.0, 24.0),
      (
        'landscape-ish, 3-button-nav insets',
        const Size(800, 400),
        24.0,
        48.0,
      ),
    ]) {
      testWidgets(
        'scrolled to the end ($label), the last entry card is fully above '
        'the FAB',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          // The FAB's own clearance is a fixed Material dimension, not a
          // device inset (see `journal_fab_clearance.dart`'s doc comment
          // for why) -- this varies the system insets across the two cases
          // to prove that half of criterion 3, that a stingier or more
          // generous status bar / gesture inset never changes whether the
          // FAB itself stays cleared, rather than because the clearance
          // number is expected to track it.
          tester.view.padding = FakeViewPadding(
            top: topInset,
            bottom: bottomInset,
          );
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            buildTestable(replies: loadReplies(entries: manyEntries())),
          );
          await tester.pumpAndSettle();

          await jumpToEnd(tester);
          await tester.pumpAndSettle();

          final fabTop = tester
              .getTopLeft(find.byType(FloatingActionButton))
              .dy;
          final lastCardBottom = tester
              .getBottomLeft(find.byType(EntryCard).last)
              .dy;

          expect(
            lastCardBottom,
            lessThanOrEqualTo(fabTop),
            reason:
                'the last entry card must be fully visible above the FAB, '
                'not merely scrolled past it',
          );
        },
      );
    }

    testWidgets(
      'the bottom list padding is journalFabScrollClearance, not a '
      're-guessed number',
      (tester) async {
        await tester.pumpWidget(buildTestable(replies: loadReplies()));
        await tester.pumpAndSettle();

        final padding =
            tester.widget<ListView>(find.byType(ListView)).padding
                as EdgeInsets;

        expect(padding.bottom, journalFabScrollClearance);
      },
    );

    testWidgets(
      "the header's top offset moves in lock-step with MediaQuery's top "
      'inset, proving it is read live rather than off a fixed guess',
      (tester) async {
        const smallInset = 24.0;
        const largeInset = 120.0;

        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        tester.view.padding = const FakeViewPadding(top: smallInset);
        await tester.pumpWidget(buildTestable(replies: loadReplies()));
        await tester.pumpAndSettle();
        final smallTop = tester.getTopLeft(find.text('Today')).dy;

        tester.view.padding = const FakeViewPadding(top: largeInset);
        await tester.pumpWidget(buildTestable(replies: loadReplies()));
        await tester.pumpAndSettle();
        final largeTop = tester.getTopLeft(find.text('Today')).dy;

        // The exact delta, not just "grew": the header's own internal
        // layout (eyebrow height, spacing) is identical between the two
        // pumps, so every logical pixel added to the simulated status bar
        // must reappear in the header's own offset, one for one.
        expect(largeTop - smallTop, largeInset - smallInset);
      },
    );
  });

  group('swipe', () {
    testWidgets('a rightward drag past the threshold moves to the '
        'previous day', (tester) async {
      await tester.pumpWidget(
        buildTestable(replies: [...loadReplies(), ...pastDayReplies()]),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(TodayScreen), const Offset(300, 0));
      await tester.pumpAndSettle();

      expect(find.text('Yesterday'), findsOneWidget);
    });

    testWidgets('a leftward drag on today does not move past today', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestable(replies: loadReplies()));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(TodayScreen), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
    });
  });

  group('errors', () {
    testWidgets('a failed load surfaces as a snack bar', (tester) async {
      await tester.pumpWidget(
        buildTestable(
          replies: [
            FakeReply(500, body: {'error': 'server exploded'}),
            FakeReply(200, body: monthlySummaryJson(days: const [])),
            FakeReply(200, body: seriesJson()),
            noActiveExperimentReply(),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('server exploded'), findsOneWidget);
    });
  });
}
