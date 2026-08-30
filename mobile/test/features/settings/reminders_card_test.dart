import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/settings/reminders_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../support/harness.dart';

void main() {
  // `RemindersController.save` schedules through `tz.TZDateTime`, which
  // needs `tz.local` set. The real app sets it via `ReminderService.
  // initialize` at startup; these tests pump `RemindersCard` on its own, so
  // it is set once here instead, the same way the app would before this
  // card ever becomes reachable.
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
  });

  // The permission and denial-note behaviour under test is Android's, which
  // matches `flutter test`'s own default `defaultTargetPlatform` -- no
  // override needed here.

  Widget app() => const MaterialApp(home: Scaffold(body: RemindersCard()));

  testWidgets(
    'a fresh install shows the two default suggestions, both off',
    (tester) async {
      await tester.pumpWidget(Harness().scope(app()));
      await tester.pumpAndSettle();

      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('21:00'), findsOneWidget);
      final switches = tester.widgetList<Switch>(find.byType(Switch));
      expect(switches.map((s) => s.value), [false, false]);
    },
  );

  testWidgets('shows every stored reminder', (tester) async {
    final harness = Harness(
      settings: const AppSettings(
        reminders: [
          ReminderTime(hour: 7, minute: 30, enabled: true),
          ReminderTime(hour: 13, minute: 0),
          ReminderTime(hour: 22, minute: 15, enabled: true),
        ],
      ),
    );
    await tester.pumpWidget(harness.scope(app()));
    await tester.pumpAndSettle();

    expect(find.text('07:30'), findsOneWidget);
    expect(find.text('13:00'), findsOneWidget);
    expect(find.text('22:15'), findsOneWidget);
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.map((s) => s.value), [true, false, true]);
  });

  testWidgets(
    'toggling one reminder among several leaves the others untouched',
    (tester) async {
      final harness = Harness(
        settings: const AppSettings(
          reminders: [
            ReminderTime(hour: 7, minute: 30, enabled: true),
            ReminderTime(hour: 13, minute: 0),
            ReminderTime(hour: 22, minute: 15, enabled: true),
          ],
        ),
      );
      await tester.pumpWidget(harness.scope(app()));
      await tester.pumpAndSettle();

      // The middle reminder is the only one that should change.
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();

      expect(harness.store.savedReminders.last, const [
        ReminderTime(hour: 7, minute: 30, enabled: true),
        ReminderTime(hour: 13, minute: 0, enabled: true),
        ReminderTime(hour: 22, minute: 15, enabled: true),
      ]);
    },
  );

  testWidgets(
    'turning a reminder on persists it and requests the platform '
    'permission',
    (tester) async {
      final harness = Harness(
        settings: const AppSettings(
          reminders: [ReminderTime(hour: 9, minute: 0)],
        ),
      );
      harness.remindersPlugin.androidPermissionResult = true;
      await tester.pumpWidget(harness.scope(app()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        harness.store.savedReminders.last,
        const [ReminderTime(hour: 9, minute: 0, enabled: true)],
      );
      expect(harness.remindersPlugin.scheduledCalls, hasLength(1));
      expect(
        find.textContaining('Notifications are off for this app'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'turning a reminder on shows the denial note when the platform refuses',
    (tester) async {
      final harness = Harness(
        settings: const AppSettings(
          reminders: [ReminderTime(hour: 9, minute: 0)],
        ),
      );
      harness.remindersPlugin.androidPermissionResult = false;
      await tester.pumpWidget(harness.scope(app()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Notifications are off for this app'),
        findsOneWidget,
      );
      expect(find.text('Grant in system settings'), findsOneWidget);
    },
  );

  testWidgets(
    'a returning user with an enabled, denied reminder sees the note '
    'immediately, without a fresh save',
    (tester) async {
      final harness = Harness(
        settings: const AppSettings(
          reminders: [ReminderTime(hour: 9, minute: 0, enabled: true)],
        ),
      );
      harness.remindersPlugin.notificationsEnabledResult = false;
      await tester.pumpWidget(harness.scope(app()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Notifications are off for this app'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping the denial note\'s link opens the OS notification settings',
    (tester) async {
      final harness = Harness(
        settings: const AppSettings(
          reminders: [ReminderTime(hour: 9, minute: 0)],
        ),
      );
      harness.remindersPlugin.androidPermissionResult = false;
      await tester.pumpWidget(harness.scope(app()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant in system settings'));
      await tester.pumpAndSettle();

      expect(harness.remindersPlugin.openNotificationSettingsCallCount, 1);
    },
  );

  testWidgets(
    'turning an enabled reminder off cancels its alarm and shows no '
    'denial note',
    (tester) async {
      final harness = Harness(
        settings: const AppSettings(
          reminders: [ReminderTime(hour: 9, minute: 0, enabled: true)],
        ),
      );
      await tester.pumpWidget(harness.scope(app()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        harness.store.savedReminders.last,
        const [ReminderTime(hour: 9, minute: 0)],
      );
      expect(harness.remindersPlugin.scheduledCalls, isEmpty);
      expect(
        find.textContaining('Notifications are off for this app'),
        findsNothing,
      );
    },
  );

  testWidgets('adding a reminder appends a new, disabled entry', (
    tester,
  ) async {
    final harness = Harness(
      settings: const AppSettings(
        reminders: [ReminderTime(hour: 9, minute: 0)],
      ),
    );
    await tester.pumpWidget(harness.scope(app()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add reminder'));
    await tester.pumpAndSettle();

    expect(
      harness.store.savedReminders.last,
      const [
        ReminderTime(hour: 9, minute: 0),
        ReminderTime(hour: 12, minute: 0),
      ],
    );
    expect(find.text('12:00'), findsOneWidget);
  });

  testWidgets(
    'the add button disappears once six reminders are configured',
    (tester) async {
      final harness = Harness(
        settings: const AppSettings(
          reminders: [
            ReminderTime(hour: 0, minute: 0),
            ReminderTime(hour: 1, minute: 0),
            ReminderTime(hour: 2, minute: 0),
            ReminderTime(hour: 3, minute: 0),
            ReminderTime(hour: 4, minute: 0),
            ReminderTime(hour: 5, minute: 0),
          ],
        ),
      );
      await tester.pumpWidget(harness.scope(app()));
      await tester.pumpAndSettle();

      expect(find.text('Add reminder'), findsNothing);
    },
  );

  testWidgets('removing a reminder persists the shorter list', (
    tester,
  ) async {
    final harness = Harness(
      settings: const AppSettings(
        reminders: [
          ReminderTime(hour: 9, minute: 0),
          ReminderTime(hour: 21, minute: 0, enabled: true),
        ],
      ),
    );
    await tester.pumpWidget(harness.scope(app()));
    await tester.pumpAndSettle();

    // #150 task 1: an icon-only control's accessible name comes from the
    // semantics tree's `label`, not `IconButton`'s own `tooltip` (which
    // only reaches the tree's separate `tooltip` field) -- see
    // `pattern_echo_panel.dart`'s dismiss button for the same distinction.
    expect(find.bySemanticsLabel('Remove 09:00 reminder'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove 09:00 reminder'));
    await tester.pumpAndSettle();

    expect(
      harness.store.savedReminders.last,
      const [ReminderTime(hour: 21, minute: 0, enabled: true)],
    );
    expect(find.text('09:00'), findsNothing);
    expect(find.text('21:00'), findsOneWidget);
  });

  testWidgets('removing the only enabled reminder cancels every alarm', (
    tester,
  ) async {
    final harness = Harness(
      settings: const AppSettings(
        reminders: [ReminderTime(hour: 9, minute: 0, enabled: true)],
      ),
    );
    await tester.pumpWidget(harness.scope(app()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove 09:00 reminder'));
    await tester.pumpAndSettle();

    expect(harness.store.savedReminders.last, isEmpty);
    expect(harness.remindersPlugin.cancelAllCallCount, greaterThan(0));
    expect(harness.remindersPlugin.scheduledCalls, isEmpty);
  });

  testWidgets('each reminder switch is labelled with its time', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final harness = Harness(
      settings: const AppSettings(
        reminders: [ReminderTime(hour: 9, minute: 0)],
      ),
    );
    await tester.pumpWidget(harness.scope(app()));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byType(Switch)).label,
      contains('09:00 reminder'),
    );
    handle.dispose();
  });

  testWidgets('cancelling the time picker changes nothing', (tester) async {
    final harness = Harness(
      settings: const AppSettings(
        reminders: [ReminderTime(hour: 9, minute: 0)],
      ),
    );
    await tester.pumpWidget(harness.scope(app()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('09:00'));
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(harness.store.savedReminders, isEmpty);
  });

  testWidgets('picking a new time persists it', (tester) async {
    final harness = Harness(
      settings: const AppSettings(
        reminders: [ReminderTime(hour: 9, minute: 0, enabled: true)],
      ),
    );
    await tester.pumpWidget(harness.scope(app()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('09:00'));
    await tester.pumpAndSettle();

    // Switch the picker to keyboard entry, so the new time can be typed
    // rather than dragged around a dial -- the only reliable way to drive
    // Material's time picker deterministically in a widget test.
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '07');
    await tester.enterText(find.byType(TextFormField).last, '45');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
      harness.store.savedReminders.last,
      const [ReminderTime(hour: 7, minute: 45, enabled: true)],
    );
  });
}
