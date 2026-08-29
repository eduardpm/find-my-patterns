import 'package:find_my_patterns/core/notifications/digest_settings_controller.dart';
import 'package:find_my_patterns/core/notifications/reminder_providers.dart';
import 'package:find_my_patterns/core/notifications/reminder_service.dart';
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
    await container.read(reminderServiceProvider).initialize();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('build', () {
    test(
      'is false when the digest is off, without checking the platform',
      () async {
        container = buildContainer(
          settings: const AppSettings(
            digest: DigestTime(weekday: DateTime.sunday, hour: 18, minute: 0),
          ),
        );

        final blocked = await container.read(
          digestSettingsControllerProvider.future,
        );

        expect(blocked, isFalse);
      },
    );

    test(
      'is true when the digest is on and the platform is off',
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
        plugin.notificationsEnabledResult = false;

        final blocked = await container.read(
          digestSettingsControllerProvider.future,
        );

        expect(blocked, isTrue);
      },
    );

    test(
      'is false when the digest is on and the platform allows it',
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
        plugin.notificationsEnabledResult = true;

        final blocked = await container.read(
          digestSettingsControllerProvider.future,
        );

        expect(blocked, isFalse);
      },
    );
  });

  group('save', () {
    const schedule = DigestTime(
      weekday: DateTime.monday,
      hour: 8,
      minute: 0,
      enabled: true,
    );

    test('persists the given schedule', () async {
      await container.read(digestSettingsControllerProvider.future);

      await container
          .read(digestSettingsControllerProvider.notifier)
          .save(schedule);

      expect(store.savedDigestSchedules.single, schedule);
    });

    test('requests the platform permission when the save turns the digest '
        'on', () async {
      await container.read(digestSettingsControllerProvider.future);
      plugin.androidPermissionResult = true;

      await container
          .read(digestSettingsControllerProvider.notifier)
          .save(schedule);

      expect(container.read(digestSettingsControllerProvider).value, isFalse);
    });

    test('reports blocked when the platform refuses the permission', () async {
      await container.read(digestSettingsControllerProvider.future);
      plugin.androidPermissionResult = false;

      await container
          .read(digestSettingsControllerProvider.notifier)
          .save(schedule);

      expect(container.read(digestSettingsControllerProvider).value, isTrue);
    });

    test('never requests the permission when the digest stays off', () async {
      await container.read(digestSettingsControllerProvider.future);

      await container
          .read(digestSettingsControllerProvider.notifier)
          .save(
            const DigestTime(weekday: DateTime.monday, hour: 8, minute: 0),
          );

      expect(plugin.androidPermissionResult, isTrue); // untouched default
      expect(container.read(digestSettingsControllerProvider).value, isFalse);
    });

    test('schedules the alarm when the save turns the digest on', () async {
      await container.read(digestSettingsControllerProvider.future);

      await container
          .read(digestSettingsControllerProvider.notifier)
          .save(schedule);

      expect(plugin.scheduledCalls, hasLength(1));
    });

    test('cancels the alarm, not every alarm, when the save turns the '
        'digest off', () async {
      await container.read(digestSettingsControllerProvider.future);
      await container
          .read(digestSettingsControllerProvider.notifier)
          .save(schedule);

      await container
          .read(digestSettingsControllerProvider.notifier)
          .save(schedule.copyWith(enabled: false));

      expect(plugin.cancelledIds, hasLength(1));
      expect(plugin.cancelAllCallCount, 0);
    });
  });

  group('rearm', () {
    test(
      'schedules the alarm from stored settings when the digest is on',
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

        await container.read(digestSettingsControllerProvider.notifier).rearm();

        expect(plugin.scheduledCalls, hasLength(1));
      },
    );

    test(
      'cancels the alarm, not every alarm, when the digest is off',
      () async {
        await container.read(digestSettingsControllerProvider.notifier).rearm();

        expect(plugin.cancelledIds, hasLength(1));
        expect(plugin.cancelAllCallCount, 0);
      },
    );
  });

  group('openSystemSettings', () {
    test('opens the OS notification-settings screen', () async {
      await container.read(digestSettingsControllerProvider.future);

      await container
          .read(digestSettingsControllerProvider.notifier)
          .openSystemSettings();

      expect(plugin.openNotificationSettingsCallCount, 1);
    });
  });
}
