import 'package:find_my_patterns/core/notifications/reminder_providers.dart';
import 'package:find_my_patterns/core/notifications/reminder_service.dart';
import 'package:find_my_patterns/core/notifications/reminder_settings_controller.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/settings/settings_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_settings_store.dart';
import 'fake_device_time_zone.dart';
import 'fake_notifications_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotificationsPlugin plugin;
  late FakeSettingsStore store;
  late ProviderContainer container;

  ProviderContainer buildContainer({
    AppSettings settings = const AppSettings(),
  }) {
    plugin = FakeNotificationsPlugin();
    store = FakeSettingsStore(settings);
    final c = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        reminderServiceProvider.overrideWithValue(
          ReminderService(plugin: plugin, deviceTimeZone: FakeDeviceTimeZone()),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    container = buildContainer();
    // `scheduleAll` needs `tz.local` set, which only `initialize` does; the
    // `build` tests below replace `container` with their own before this
    // has any effect on them, so it only matters to the `save` group.
    await container.read(reminderServiceProvider).initialize();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('build', () {
    test(
      'is false when nothing is enabled, without checking the platform',
      () async {
        container = buildContainer(
          settings: const AppSettings(
            reminders: [ReminderTime(hour: 9, minute: 0)],
          ),
        );

        final blocked = await container.read(
          remindersControllerProvider.future,
        );

        expect(blocked, isFalse);
      },
    );

    test(
      'is true when an enabled reminder exists and the platform is off',
      () async {
        container = buildContainer(
          settings: const AppSettings(
            reminders: [ReminderTime(hour: 9, minute: 0, enabled: true)],
          ),
        );
        plugin.notificationsEnabledResult = false;

        final blocked = await container.read(
          remindersControllerProvider.future,
        );

        expect(blocked, isTrue);
      },
    );

    test(
      'is false when an enabled reminder exists and the platform allows it',
      () async {
        container = buildContainer(
          settings: const AppSettings(
            reminders: [ReminderTime(hour: 9, minute: 0, enabled: true)],
          ),
        );
        plugin.notificationsEnabledResult = true;

        final blocked = await container.read(
          remindersControllerProvider.future,
        );

        expect(blocked, isFalse);
      },
    );
  });

  group('save', () {
    test('persists the given reminders', () async {
      await container.read(remindersControllerProvider.future);

      const reminders = [ReminderTime(hour: 8, minute: 0)];
      await container
          .read(remindersControllerProvider.notifier)
          .save(reminders);

      expect(store.savedReminders.single, reminders);
    });

    test(
      'requests the platform permission when the save leaves a reminder '
      'enabled',
      () async {
        await container.read(remindersControllerProvider.future);
        plugin.androidPermissionResult = true;

        await container.read(remindersControllerProvider.notifier).save(const [
          ReminderTime(hour: 8, minute: 0, enabled: true),
        ]);

        expect(
          container.read(remindersControllerProvider).value,
          isFalse,
        );
      },
    );

    test(
      'reports blocked when the platform refuses the permission',
      () async {
        await container.read(remindersControllerProvider.future);
        plugin.androidPermissionResult = false;

        await container.read(remindersControllerProvider.notifier).save(const [
          ReminderTime(hour: 8, minute: 0, enabled: true),
        ]);

        expect(container.read(remindersControllerProvider).value, isTrue);
      },
    );

    test(
      'never requests the permission when nothing is enabled',
      () async {
        await container.read(remindersControllerProvider.future);

        await container.read(remindersControllerProvider.notifier).save(const [
          ReminderTime(hour: 8, minute: 0),
        ]);

        expect(plugin.androidPermissionResult, isTrue); // untouched default
        expect(container.read(remindersControllerProvider).value, isFalse);
      },
    );

    test('reschedules only the enabled slots', () async {
      await container.read(remindersControllerProvider.future);

      await container.read(remindersControllerProvider.notifier).save(const [
        ReminderTime(hour: 8, minute: 0, enabled: true),
        ReminderTime(hour: 12, minute: 0),
        ReminderTime(hour: 20, minute: 30, enabled: true),
      ]);

      expect(
        plugin.scheduledCalls.map((call) => call.id).toSet(),
        {8 * 60, 20 * 60 + 30},
      );
    });

    test(
      'reconciles against the plugin rather than calling cancelAll (#153)',
      () async {
        await container.read(remindersControllerProvider.future);

        await container.read(remindersControllerProvider.notifier).save(const [
          ReminderTime(hour: 8, minute: 0, enabled: true),
        ]);

        expect(plugin.cancelAllCallCount, 0);
        expect(
          plugin.scheduledCalls.map((call) => call.id),
          contains(8 * 60),
        );
      },
    );

    test(
      'cancels every alarm and schedules nothing when no reminder is '
      'enabled',
      () async {
        await container.read(remindersControllerProvider.future);

        await container.read(remindersControllerProvider.notifier).save(const [
          ReminderTime(hour: 8, minute: 0),
        ]);

        expect(plugin.cancelAllCallCount, 0);
        expect(plugin.scheduledCalls, isEmpty);
      },
    );

    test(
      'turning a reminder off cancels the alarm it used to hold (#153)',
      () async {
        await container.read(remindersControllerProvider.future);
        await container.read(remindersControllerProvider.notifier).save(const [
          ReminderTime(hour: 9, minute: 0, enabled: true),
        ]);
        expect(plugin.scheduledCalls.map((c) => c.id), contains(9 * 60));

        await container.read(remindersControllerProvider.notifier).save(const [
          ReminderTime(hour: 9, minute: 0),
        ]);

        expect(plugin.cancelledIds, contains(9 * 60));
        expect(plugin.pendingIds, isEmpty);
      },
    );

    test(
      'removing a reminder cancels the alarm it used to hold (#153)',
      () async {
        await container.read(remindersControllerProvider.future);
        await container.read(remindersControllerProvider.notifier).save(const [
          ReminderTime(hour: 9, minute: 0, enabled: true),
          ReminderTime(hour: 21, minute: 0, enabled: true),
        ]);
        expect(
          plugin.scheduledCalls.map((c) => c.id).toSet(),
          {9 * 60, 21 * 60},
        );

        await container.read(remindersControllerProvider.notifier).save(const [
          ReminderTime(hour: 21, minute: 0, enabled: true),
        ]);

        expect(plugin.cancelledIds, contains(9 * 60));
        expect(plugin.pendingIds, {21 * 60});
      },
    );

    test(
      'changing a reminder\'s time cancels the old id and schedules the '
      'new one (#153)',
      () async {
        await container.read(remindersControllerProvider.future);
        await container.read(remindersControllerProvider.notifier).save(const [
          ReminderTime(hour: 9, minute: 0, enabled: true),
        ]);
        expect(plugin.scheduledCalls.map((c) => c.id), contains(9 * 60));

        await container.read(remindersControllerProvider.notifier).save(const [
          ReminderTime(hour: 10, minute: 30, enabled: true),
        ]);

        expect(plugin.cancelledIds, contains(9 * 60));
        expect(plugin.pendingIds, {10 * 60 + 30});
      },
    );

    test(
      'two concurrent saves apply in call order, so the later call\'s '
      'cancel is not overwritten by the earlier call\'s schedule (#153)',
      () async {
        await container.read(remindersControllerProvider.future);
        final notifier = container.read(remindersControllerProvider.notifier);

        // Mirrors `reminders_card.dart`'s `unawaited(controller.save(...))`
        // on every toggle, time change, add and remove: neither call is
        // awaited before the next one fires, so both bodies can be in
        // flight together.
        final first = notifier.save(const [
          ReminderTime(hour: 21, minute: 0, enabled: true),
        ]);
        final second = notifier.save(const [ReminderTime(hour: 21, minute: 0)]);
        await Future.wait([first, second]);

        // `second` was issued after `first`, so it must be the state both
        // the persisted settings and the scheduled alarms agree on: nothing
        // armed at 21:00, matching the "off" setting `second` saved.
        expect(
          store.savedReminders.last,
          const [ReminderTime(hour: 21, minute: 0)],
        );
        expect(plugin.pendingIds, isEmpty);
      },
    );

    test(
      're-arms the digest afterwards, so cancelAll above does not leave it '
      'silently cancelled (R-2)',
      () async {
        container = buildContainer(
          settings: const AppSettings(
            digest: DigestTime(
              weekday: DateTime.sunday,
              hour: 18,
              minute: 0,
              enabled: true,
            ),
          ),
        );
        await container.read(reminderServiceProvider).initialize();
        await container.read(remindersControllerProvider.future);

        await container.read(remindersControllerProvider.notifier).save(const [
          ReminderTime(hour: 8, minute: 0, enabled: true),
        ]);

        // One reminder alarm plus the re-armed digest alarm -- both present
        // after the same `cancelAll` that would otherwise have wiped the
        // digest's own independently-scheduled notification.
        expect(plugin.scheduledCalls, hasLength(2));
      },
    );

    test(
      'does not re-arm the digest when it is off, only cancel it',
      () async {
        await container.read(remindersControllerProvider.future);

        await container.read(remindersControllerProvider.notifier).save(const [
          ReminderTime(hour: 8, minute: 0, enabled: true),
        ]);

        // The one reminder alarm, and nothing scheduled for the (off)
        // digest -- `DigestSettingsController.rearm` cancels rather than
        // schedules when `AppSettings.digest.enabled` is false.
        expect(plugin.scheduledCalls, hasLength(1));
        expect(plugin.cancelledIds, isNotEmpty);
      },
    );
  });

  group('openSystemSettings', () {
    test('opens the OS notification-settings screen', () async {
      await container.read(remindersControllerProvider.future);

      await container
          .read(remindersControllerProvider.notifier)
          .openSystemSettings();

      expect(plugin.openNotificationSettingsCallCount, 1);
    });
  });
}
