import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart';

/// The slice of `flutter_local_notifications`' surface `ReminderService`
/// actually calls.
///
/// [FlutterLocalNotificationsPlugin] is a concrete class behind a factory
/// singleton, with the platform-specific permission calls tucked behind
/// `resolvePlatformSpecificImplementation`. Faking that whole shape in a
/// test would mean standing up a fake for a surface `ReminderService` never
/// touches. This interface names only what is actually called, so a test
/// double stays a handful of methods instead of a plugin.
abstract interface class NotificationsPlugin {
  /// Initialises the plugin for this platform.
  ///
  /// [onTap] fires when the user taps a notification while the app is
  /// already running (a cold start is read separately, from
  /// [getNotificationAppLaunchDetails]).
  Future<void> initialize({
    required InitializationSettings settings,
    required void Function(NotificationResponse response) onTap,
  });

  /// Schedules one notification at [scheduledDate], repeating according to
  /// [matchDateTimeComponents].
  ///
  /// `ReminderService` always passes [DateTimeComponents.time], for a daily
  /// repeat at the same wall-clock time — [matchDateTimeComponents] stays a
  /// parameter here, rather than a constant baked into the implementation,
  /// so a test can see which repeat policy a call actually asked for.
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    required DateTimeComponents matchDateTimeComponents,
    required String payload,
  });

  /// Cancels every notification scheduled through this plugin.
  Future<void> cancelAll();

  /// Whether a notification from this plugin launched the app, and if so,
  /// which one — a cold start, as opposed to a tap [initialize]'s `onTap`
  /// catches while already running.
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails();

  /// Requests Android 13+'s runtime notification permission.
  ///
  /// `null` on any platform other than Android, where there is nothing to
  /// request.
  Future<bool?> requestAndroidNotificationsPermission();

  /// Requests iOS/macOS's notification permission (alert, sound, badge).
  ///
  /// `null` on any platform other than Darwin ones.
  Future<bool?> requestDarwinNotificationsPermission();
}

/// The real [NotificationsPlugin], backed by the plugin's own singleton.
///
/// Holds no state of its own — [FlutterLocalNotificationsPlugin]'s factory
/// constructor already returns a process-wide singleton — so this stays a
/// plain `const` adapter rather than something `ReminderService` needs to be
/// handed a particular instance of.
class const DefaultNotificationsPlugin() implements NotificationsPlugin {
  FlutterLocalNotificationsPlugin get _plugin =>
      FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize({
    required InitializationSettings settings,
    required void Function(NotificationResponse response) onTap,
  }) async {
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onTap,
    );
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    required DateTimeComponents matchDateTimeComponents,
    required String payload,
  }) => _plugin.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: scheduledDate,
    notificationDetails: notificationDetails,
    androidScheduleMode: androidScheduleMode,
    matchDateTimeComponents: matchDateTimeComponents,
    payload: payload,
  );

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() =>
      _plugin.getNotificationAppLaunchDetails();

  @override
  Future<bool?> requestAndroidNotificationsPermission() async => await _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();

  @override
  Future<bool?> requestDarwinNotificationsPermission() async => await _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >()
      ?.requestPermissions(alert: true, badge: true, sound: true);
}
