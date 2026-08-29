import 'package:find_my_patterns/core/notifications/notifications_plugin.dart';
import 'package:find_my_patterns/core/notifications/reminder_providers.dart';
import 'package:find_my_patterns/core/notifications/reminder_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_device_time_zone.dart';
import 'fake_notifications_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotificationsPlugin plugin;
  late ProviderContainer container;

  setUp(() {
    plugin = FakeNotificationsPlugin();
    container = ProviderContainer(
      overrides: [
        reminderServiceProvider.overrideWithValue(
          ReminderService(plugin: plugin, deviceTimeZone: FakeDeviceTimeZone()),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  test('the default service is backed by the real plugin', () {
    final defaultContainer = ProviderContainer();
    addTearDown(defaultContainer.dispose);
    expect(
      defaultContainer.read(reminderServiceProvider).plugin,
      isA<DefaultNotificationsPlugin>(),
    );
  });

  test('openComposerSignalProvider starts at zero', () {
    expect(container.read(openComposerSignalProvider), 0);
  });

  test('increments once per tap reported while the app is running', () async {
    // Start listening so the underlying StreamProvider is alive to observe
    // the fake plugin's tap.
    container.listen(openComposerSignalProvider, (_, _) {});
    await container.read(reminderServiceProvider).initialize();

    plugin.fireTap(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: '540',
      ),
    );
    await pumpEventQueue();

    expect(container.read(openComposerSignalProvider), 1);
  });

  test('a second tap increments again rather than staying at one', () async {
    container.listen(openComposerSignalProvider, (_, _) {});
    await container.read(reminderServiceProvider).initialize();

    for (var i = 0; i < 2; i++) {
      plugin.fireTap(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '540',
        ),
      );
      await pumpEventQueue();
    }

    expect(container.read(openComposerSignalProvider), 2);
  });

  group('checkLaunchTap', () {
    test('increments when a reminder cold-started the app', () async {
      plugin.launchDetails = const NotificationAppLaunchDetails(
        true,
        notificationResponse: NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '540',
        ),
      );

      await container
          .read(openComposerSignalProvider.notifier)
          .checkLaunchTap();

      expect(container.read(openComposerSignalProvider), 1);
    });

    test('does nothing when nothing launched the app', () async {
      plugin.launchDetails = const NotificationAppLaunchDetails(false);

      await container
          .read(openComposerSignalProvider.notifier)
          .checkLaunchTap();

      expect(container.read(openComposerSignalProvider), 0);
    });

    test(
      'a first-pattern launch tap does not open the composer (#38)',
      () async {
        plugin.launchDetails = const NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: 'first_pattern',
          ),
        );

        await container
            .read(openComposerSignalProvider.notifier)
            .checkLaunchTap();

        expect(container.read(openComposerSignalProvider), 0);
      },
    );
  });

  group('openInsightsSignalProvider (#38)', () {
    test('starts at zero', () {
      expect(container.read(openInsightsSignalProvider), 0);
    });

    test('increments on a first-pattern tap reported while running', () async {
      container.listen(openInsightsSignalProvider, (_, _) {});
      await container.read(reminderServiceProvider).initialize();

      plugin.fireTap(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'first_pattern',
        ),
      );
      await pumpEventQueue();

      expect(container.read(openInsightsSignalProvider), 1);
    });

    test('a reminder tap does not open Insights', () async {
      container.listen(openInsightsSignalProvider, (_, _) {});
      await container.read(reminderServiceProvider).initialize();

      plugin.fireTap(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '540',
        ),
      );
      await pumpEventQueue();

      expect(container.read(openInsightsSignalProvider), 0);
    });

    test('bump signals Insights directly, for the inline celebration card\'s '
        'own tap', () {
      container.read(openInsightsSignalProvider.notifier).bump();

      expect(container.read(openInsightsSignalProvider), 1);
    });

    group('checkLaunchTap', () {
      test('increments when the first-pattern notification cold-started '
          'the app', () async {
        plugin.launchDetails = const NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: 'first_pattern',
          ),
        );

        await container
            .read(openInsightsSignalProvider.notifier)
            .checkLaunchTap();

        expect(container.read(openInsightsSignalProvider), 1);
      });

      test('a reminder launch tap does not open Insights', () async {
        plugin.launchDetails = const NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: '540',
          ),
        );

        await container
            .read(openInsightsSignalProvider.notifier)
            .checkLaunchTap();

        expect(container.read(openInsightsSignalProvider), 0);
      });

      test('does nothing when nothing launched the app', () async {
        plugin.launchDetails = const NotificationAppLaunchDetails(false);

        await container
            .read(openInsightsSignalProvider.notifier)
            .checkLaunchTap();

        expect(container.read(openInsightsSignalProvider), 0);
      });
    });
  });

  group('openDigestSignalProvider (R-2)', () {
    test('starts at zero', () {
      expect(container.read(openDigestSignalProvider), 0);
    });

    test('increments on a digest tap reported while running', () async {
      container.listen(openDigestSignalProvider, (_, _) {});
      await container.read(reminderServiceProvider).initialize();

      plugin.fireTap(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'weekly_digest',
        ),
      );
      await pumpEventQueue();

      expect(container.read(openDigestSignalProvider), 1);
    });

    test('a second tap increments again rather than staying at one', () async {
      container.listen(openDigestSignalProvider, (_, _) {});
      await container.read(reminderServiceProvider).initialize();

      for (var i = 0; i < 2; i++) {
        plugin.fireTap(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: 'weekly_digest',
          ),
        );
        await pumpEventQueue();
      }

      expect(container.read(openDigestSignalProvider), 2);
    });

    test('a reminder tap does not open the digest', () async {
      container.listen(openDigestSignalProvider, (_, _) {});
      await container.read(reminderServiceProvider).initialize();

      plugin.fireTap(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '540',
        ),
      );
      await pumpEventQueue();

      expect(container.read(openDigestSignalProvider), 0);
    });

    test('a first-pattern tap does not open the digest', () async {
      container.listen(openDigestSignalProvider, (_, _) {});
      await container.read(reminderServiceProvider).initialize();

      plugin.fireTap(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'first_pattern',
        ),
      );
      await pumpEventQueue();

      expect(container.read(openDigestSignalProvider), 0);
    });

    group('checkLaunchTap', () {
      test(
        'increments when the digest notification cold-started the app',
        () async {
          plugin.launchDetails = const NotificationAppLaunchDetails(
            true,
            notificationResponse: NotificationResponse(
              notificationResponseType:
                  NotificationResponseType.selectedNotification,
              payload: 'weekly_digest',
            ),
          );

          await container
              .read(openDigestSignalProvider.notifier)
              .checkLaunchTap();

          expect(container.read(openDigestSignalProvider), 1);
        },
      );

      test('a reminder launch tap does not open the digest', () async {
        plugin.launchDetails = const NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: '540',
          ),
        );

        await container
            .read(openDigestSignalProvider.notifier)
            .checkLaunchTap();

        expect(container.read(openDigestSignalProvider), 0);
      });

      test('does nothing when nothing launched the app', () async {
        plugin.launchDetails = const NotificationAppLaunchDetails(false);

        await container
            .read(openDigestSignalProvider.notifier)
            .checkLaunchTap();

        expect(container.read(openDigestSignalProvider), 0);
      });
    });
  });
}
