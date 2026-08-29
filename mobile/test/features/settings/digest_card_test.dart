import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/features/settings/digest_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../support/harness.dart';

void main() {
  // `DigestSettingsController.save` schedules through `tz.TZDateTime`, the
  // same reason `reminders_card_test.dart` sets this up before pumping its
  // own card.
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
  });

  Widget app() => const MaterialApp(home: Scaffold(body: DigestCard()));

  testWidgets('a fresh install shows the default schedule, off', (
    tester,
  ) async {
    await tester.pumpWidget(Harness().scope(app()));
    await tester.pumpAndSettle();

    expect(find.text('Sunday'), findsOneWidget);
    expect(find.text('18:00'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('shows a stored schedule', (tester) async {
    final harness = Harness(
      settings: const AppSettings(
        digest: DigestTime(
          weekday: DateTime.wednesday,
          hour: 7,
          minute: 15,
          enabled: true,
        ),
      ),
    );
    await tester.pumpWidget(harness.scope(app()));
    await tester.pumpAndSettle();

    expect(find.text('Wednesday'), findsOneWidget);
    expect(find.text('07:15'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets(
    'turning the digest on persists it and requests the platform permission',
    (tester) async {
      final harness = Harness();
      harness.remindersPlugin.androidPermissionResult = true;
      await tester.pumpWidget(harness.scope(app()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        harness.store.savedDigestSchedules.last,
        const DigestTime(
          weekday: DateTime.sunday,
          hour: 18,
          minute: 0,
          enabled: true,
        ),
      );
      expect(harness.remindersPlugin.scheduledCalls, hasLength(1));
      expect(
        find.textContaining('Notifications are off for this app'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'turning the digest on shows the denial note when the platform refuses',
    (tester) async {
      final harness = Harness();
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
    'turning the digest off persists it and cancels the alarm, not every '
    'alarm',
    (tester) async {
      final harness = Harness(
        settings: const AppSettings(
          digest: DigestTime(
            weekday: DateTime.sunday,
            hour: 18,
            minute: 0,
            enabled: true,
          ),
        ),
      );
      await tester.pumpWidget(harness.scope(app()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        harness.store.savedDigestSchedules.last,
        const DigestTime(weekday: DateTime.sunday, hour: 18, minute: 0),
      );
      expect(harness.remindersPlugin.cancelledIds, isNotEmpty);
      expect(harness.remindersPlugin.cancelAllCallCount, 0);
    },
  );

  testWidgets('choosing a different weekday persists it', (tester) async {
    final harness = Harness();
    await tester.pumpWidget(harness.scope(app()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sunday'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monday').last);
    await tester.pumpAndSettle();

    expect(
      harness.store.savedDigestSchedules.last,
      const DigestTime(weekday: DateTime.monday, hour: 18, minute: 0),
    );
  });

  testWidgets(
    'a returning user with the digest on and denied sees the note '
    'immediately, without a fresh save',
    (tester) async {
      final harness = Harness(
        settings: const AppSettings(
          digest: DigestTime(
            weekday: DateTime.sunday,
            hour: 18,
            minute: 0,
            enabled: true,
          ),
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
}
