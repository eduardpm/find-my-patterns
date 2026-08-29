import 'package:find_my_patterns/core/config/config_providers.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/network/network_providers.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:find_my_patterns/core/widgets/journal.dart';
import 'package:find_my_patterns/features/today/entry_card.dart';
import 'package:find_my_patterns/features/today/today_controller.dart';
import 'package:find_my_patterns/features/today/today_screen.dart';
import 'package:find_my_patterns/features/today/writing_streak_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../support/fake_http.dart';
import '../../support/harness.dart';
import 'json_fixtures.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 8, 28, 10);
  final today = CalendarDate.today(now: fixedNow);
  final feelingsReply = FakeReply(200, body: feelingsCatalogJson());

  /// One `refresh`'s worth of replies while showing *today*, once the
  /// feelings catalog is cached: entries, the monthly summary, then the
  /// writing-streak series (#40) -- see `today_controller_test.dart`'s
  /// identically-named helper for why a load of a past day needs
  /// [pastDayReplies] instead.
  List<FakeReply> loadReplies({
    List<Map<String, Object?>> entries = const [],
    List<Map<String, Object?>> days = const [],
    List<CalendarDate> streakDays = const [],
  }) => [
    FakeReply(200, body: entriesJson(entries)),
    FakeReply(200, body: monthlySummaryJson(days: days)),
    FakeReply(200, body: seriesJson(days: streakDays)),
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
        todayControllerProvider.overrideWith(
          () => TodayController(now: () => fixedNow, delay: (_) async {}),
        ),
      ],
      child: MaterialApp(
        home: TodayScreen(onNewEntry: onNewEntry, onOpenEntry: onOpenEntry),
      ),
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
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('server exploded'), findsOneWidget);
    });
  });
}
