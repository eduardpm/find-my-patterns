import 'package:find_my_patterns/core/notifications/notifications_plugin.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart';

/// One call `FakeNotificationsPlugin.zonedSchedule` recorded.
class ScheduledCall {
  ScheduledCall({
    required this.id,
    required this.scheduledDate,
    required this.androidScheduleMode,
    required this.matchDateTimeComponents,
    required this.payload,
  });

  final int id;
  final TZDateTime scheduledDate;
  final AndroidScheduleMode androidScheduleMode;
  final DateTimeComponents matchDateTimeComponents;
  final String payload;
}

/// An in-memory [NotificationsPlugin] double.
///
/// Records every call so a test can assert on what `ReminderService` asked
/// for, and lets a test script failures and cold-start details rather than
/// touching a real platform channel.
class FakeNotificationsPlugin implements NotificationsPlugin {
  /// Every call `initialize` received.
  final List<void Function(NotificationResponse response)> onTapCallbacks = [];

  /// Every call `zonedSchedule` received, in order.
  final List<ScheduledCall> scheduledCalls = [];

  /// Incremented on every `cancelAll` call.
  int cancelAllCallCount = 0;

  /// Set to make the next `zonedSchedule` call throw, standing in for the
  /// exact-alarm permission being revoked.
  PlatformException? nextZonedScheduleError;

  /// Answered by `getNotificationAppLaunchDetails`.
  NotificationAppLaunchDetails? launchDetails;

  /// Answered by `requestAndroidNotificationsPermission`.
  bool? androidPermissionResult = true;

  /// Answered by `requestDarwinNotificationsPermission`.
  bool? darwinPermissionResult = true;

  /// Answered by `areNotificationsEnabled`.
  bool? notificationsEnabledResult = true;

  /// Answered by `openNotificationSettings`.
  bool? openNotificationSettingsResult = true;

  /// Incremented on every `openNotificationSettings` call.
  int openNotificationSettingsCallCount = 0;

  @override
  Future<void> initialize({
    required InitializationSettings settings,
    required void Function(NotificationResponse response) onTap,
  }) async {
    onTapCallbacks.add(onTap);
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
  }) async {
    if (nextZonedScheduleError case final error?) {
      nextZonedScheduleError = null;
      throw error;
    }
    scheduledCalls.add(
      ScheduledCall(
        id: id,
        scheduledDate: scheduledDate,
        androidScheduleMode: androidScheduleMode,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      ),
    );
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCallCount++;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => launchDetails;

  @override
  Future<bool?> requestAndroidNotificationsPermission() async =>
      androidPermissionResult;

  @override
  Future<bool?> requestDarwinNotificationsPermission() async =>
      darwinPermissionResult;

  @override
  Future<bool?> areNotificationsEnabled() async => notificationsEnabledResult;

  @override
  Future<bool?> openNotificationSettings() async {
    openNotificationSettingsCallCount++;
    return openNotificationSettingsResult;
  }

  /// Simulates the plugin reporting a tap while the app is running.
  void fireTap(NotificationResponse response) {
    for (final callback in onTapCallbacks) {
      callback(response);
    }
  }
}
