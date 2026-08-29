import 'package:find_my_patterns/core/notifications/reminder_schedule.dart';
import 'package:find_my_patterns/core/notifications/reminder_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'fake_device_time_zone.dart';
import 'fake_notifications_plugin.dart';

/// A representative set of slots to schedule -- the service no longer owns
/// a fixed list of its own, so tests supply one, standing in for whatever
/// `RemindersController` would derive from the user's enabled reminders.
const _testSlots = [
  ReminderSlot(9, 0),
  ReminderSlot(12, 0),
  ReminderSlot(18, 0),
  ReminderSlot(21, 0),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotificationsPlugin plugin;
  late FakeDeviceTimeZone deviceTimeZone;
  late ReminderService service;

  setUp(() {
    plugin = FakeNotificationsPlugin();
    deviceTimeZone = FakeDeviceTimeZone();
    service = ReminderService(plugin: plugin, deviceTimeZone: deviceTimeZone);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('initialize', () {
    test('registers a tap callback with the plugin', () async {
      await service.initialize();
      expect(plugin.onTapCallbacks, hasLength(1));
    });

    test('sets the local time zone to the device\'s real zone', () async {
      deviceTimeZone.name = 'Europe/Budapest';
      await service.initialize();
      expect(tz.local.name, 'Europe/Budapest');
    });

    test('falls back to UTC when the platform lookup fails', () async {
      deviceTimeZone.nextError = PlatformException(code: 'unavailable');
      await service.initialize();
      expect(tz.local, tz.UTC);
    });

    test(
      'falls back to UTC when the reported zone name is unknown',
      () async {
        deviceTimeZone.name = 'Not/AZone';
        await service.initialize();
        expect(tz.local, tz.UTC);
      },
    );

    test(
      'the resolved zone carries real DST rules, so a reminder keeps its '
      'wall-clock hour across a DST boundary',
      () async {
        deviceTimeZone.name = 'Europe/Budapest';
        await service.initialize();

        // Europe/Budapest springs forward on the last Sunday in March: 27
        // March 2027 is still CET (UTC+1), 29 March 2027 is already CEST
        // (UTC+2). A reminder set for 09:00 on either side must still read
        // as 09:00 -- that's what lets flutter_local_notifications' native
        // daily-repeat matching land on the right wall-clock hour after the
        // shift, rather than drifting by an hour the way a fixed Etc/GMT
        // offset would.
        final beforeDst = tz.TZDateTime(tz.local, 2027, 3, 27, 9);
        final afterDst = tz.TZDateTime(tz.local, 2027, 3, 29, 9);

        expect(beforeDst.hour, 9);
        expect(afterDst.hour, 9);
        expect(beforeDst.timeZoneOffset, const Duration(hours: 1));
        expect(afterDst.timeZoneOffset, const Duration(hours: 2));
      },
    );
  });

  group('scheduleAll', () {
    test('schedules every given slot with a daily time match', () async {
      await service.scheduleAll(slots: _testSlots);

      expect(plugin.scheduledCalls, hasLength(_testSlots.length));
      expect(
        plugin.scheduledCalls.map((call) => call.id).toSet(),
        _testSlots.map((slot) => slot.id).toSet(),
      );
      for (final call in plugin.scheduledCalls) {
        expect(call.matchDateTimeComponents, DateTimeComponents.time);
        expect(
          call.androidScheduleMode,
          AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
    });

    test('schedules nothing for an empty slot list', () async {
      await service.scheduleAll(slots: const []);
      expect(plugin.scheduledCalls, isEmpty);
    });

    test('payload identifies which slot the schedule call is for', () async {
      await service.scheduleAll(slots: _testSlots);

      final payloads = plugin.scheduledCalls
          .map((call) => call.payload)
          .toSet();
      expect(payloads, _testSlots.map((slot) => '${slot.id}').toSet());
    });

    test(
      'falls back to an inexact schedule when the exact one is refused',
      () async {
        plugin.nextZonedScheduleError = PlatformException(
          code: 'exact_alarms_not_permitted',
        );

        await service.scheduleAll(slots: _testSlots);

        expect(plugin.scheduledCalls, hasLength(_testSlots.length));
        expect(
          plugin.scheduledCalls.first.androidScheduleMode,
          AndroidScheduleMode.inexactAllowWhileIdle,
        );
        // The other slots were never refused, so they still went out as
        // exact schedules -- one revoked permission doesn't degrade every
        // slot, only the ones that hit it.
        expect(
          plugin.scheduledCalls.skip(1).map((call) => call.androidScheduleMode),
          everyElement(AndroidScheduleMode.exactAllowWhileIdle),
        );
      },
    );
  });

  group('cancelAll', () {
    test('cancels every scheduled notification', () async {
      await service.cancelAll();
      expect(plugin.cancelAllCallCount, 1);
    });
  });

  group('requestPermission', () {
    test('requests the Android permission on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      plugin.androidPermissionResult = true;

      final granted = await service.requestPermission();

      expect(granted, isTrue);
    });

    test(
      'reports ungranted rather than throwing when Android refuses',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        plugin.androidPermissionResult = false;

        final granted = await service.requestPermission();

        expect(granted, isFalse);
      },
    );

    test('requests the Darwin permission on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      plugin.darwinPermissionResult = true;

      final granted = await service.requestPermission();

      expect(granted, isTrue);
    });

    test(
      'is false rather than throwing on a platform with nothing to ask',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;

        final granted = await service.requestPermission();

        expect(granted, isFalse);
      },
    );
  });

  group('notificationsEnabled', () {
    test('reads the Android answer without prompting', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      plugin.notificationsEnabledResult = false;

      expect(await service.notificationsEnabled(), isFalse);
    });

    test('reflects a granted Android answer', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      plugin.notificationsEnabledResult = true;

      expect(await service.notificationsEnabled(), isTrue);
    });

    test('is true on a platform with no equivalent read-only check', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await service.notificationsEnabled(), isTrue);
    });
  });

  group('openNotificationSettings', () {
    test('opens the Android notification-settings screen', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      plugin.openNotificationSettingsResult = true;

      final opened = await service.openNotificationSettings();

      expect(opened, isTrue);
      expect(plugin.openNotificationSettingsCallCount, 1);
    });

    test('reports false rather than throwing off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final opened = await service.openNotificationSettings();

      expect(opened, isFalse);
      expect(plugin.openNotificationSettingsCallCount, 0);
    });
  });

  group('launchTap', () {
    test('is null when nothing launched the app', () async {
      plugin.launchDetails = const NotificationAppLaunchDetails(false);
      expect(await service.launchTap(), isNull);
    });

    test('is null when the plugin has nothing to report', () async {
      plugin.launchDetails = null;
      expect(await service.launchTap(), isNull);
    });

    test('detects a cold start from a reminder tap', () async {
      plugin.launchDetails = const NotificationAppLaunchDetails(
        true,
        notificationResponse: NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '540',
        ),
      );

      final tap = await service.launchTap();

      expect(tap, const ReminderTap(540));
    });
  });

  group('taps', () {
    test('emits a tap reported while the app is running', () async {
      await service.initialize();

      final future = service.taps.first;
      plugin.fireTap(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '720',
        ),
      );

      expect(await future, const ReminderTap(720));
    });
  });
}
