import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'device_time_zone.dart';
import 'notifications_plugin.dart';
import 'reminder_schedule.dart';

/// A reminder notification the user tapped, cold or warm.
///
/// Carries [slotId] rather than a [ReminderSlot] itself: the tap is
/// identified from the notification payload the plugin hands back, which is
/// a bare string, and a slot lookup is something the app shell can do with
/// [kReminderTimes] if it ever needs the hour and minute back.
final class const ReminderTap(final int slotId) {
  @override
  bool operator ==(Object other) =>
      other is ReminderTap && other.slotId == slotId;

  @override
  int get hashCode => slotId.hashCode;

  @override
  String toString() => 'ReminderTap($slotId)';
}

/// The channel and notification the four daily reminders are shown under.
///
/// Ported from `ReminderNotifier` (Kotlin) and
/// `android/app/src/main/res/values/strings.xml`.
const String _channelId = 'diary_reminders';
const String _channelName = 'Diary check-ins';
const String _channelDescription =
    'Prompts to log a diary entry at 9:00, 12:00, 18:00 and 21:00';
const String _notificationTitle = 'Time to check in';
const String _notificationBody =
    'How are you doing right now? Log a quick entry.';

/// Schedules and reacts to the four fixed daily check-in reminders.
///
/// Ported from `ReminderScheduler`, `ReminderNotifier` and
/// `ReminderReceiver` (Kotlin), collapsed into one class because
/// `flutter_local_notifications`'s [NotificationsPlugin.zonedSchedule] does
/// what those three Kotlin classes existed to work around: `AlarmManager`
/// has no daily repeat that survives Doze, so the Kotlin schedules each slot
/// as a one-shot alarm and has `ReminderReceiver` re-arm it every time it
/// fires.
/// `zonedSchedule`'s `matchDateTimeComponents: DateTimeComponents.time`
/// repeats daily and re-arms itself — including across a reboot, which the
/// Android manifest's already-declared `flutter_local_notifications`
/// receivers handle — so there is no manual re-arm loop to port.
class ReminderService {
  /// Creates a service over [plugin] and [deviceTimeZone].
  ///
  /// Both are constructor parameters — not defaults baked into this class —
  /// specifically so a test can inject fakes instead of talking to a real
  /// platform channel. [deviceTimeZone] defaults to the real
  /// [FlutterDeviceTimeZone] so production call sites don't have to name it.
  ReminderService({
    required this.plugin,
    this.deviceTimeZone = const FlutterDeviceTimeZone(),
  });

  /// The plugin this service drives.
  final NotificationsPlugin plugin;

  /// Resolves the device's real time zone, for [initialize].
  final DeviceTimeZone deviceTimeZone;

  final StreamController<ReminderTap> _tapController =
      StreamController<ReminderTap>.broadcast();

  /// Emits a [ReminderTap] each time the user taps a reminder notification
  /// while the app is already running.
  ///
  /// A cold start is not reported here — read it once from [launchTap]
  /// instead, since by the time this stream has a listener the launch
  /// notification response has already happened.
  Stream<ReminderTap> get taps => _tapController.stream;

  /// Initialises the plugin and the time zone database.
  ///
  /// Must be called once before [scheduleAll] or [requestPermission]. Does
  /// not itself request the notification permission — see
  /// [requestPermission] — so that a caller controls exactly when the
  /// permission prompt appears.
  Future<void> initialize() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(await _deviceLocation());
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onTap: _handleTap,
    );
  }

  /// Requests the platform's notification permission.
  ///
  /// Returns whether it was granted. Never granting it is not an error —
  /// [scheduleAll] still succeeds and the reminders still fire as scheduled
  /// alarms; without the permission, nothing is shown for them, mirroring
  /// the Kotlin's `ReminderNotifier.showReminder` early return on a missing
  /// `POST_NOTIFICATIONS` grant.
  Future<bool> requestPermission() async {
    final granted = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await plugin.requestAndroidNotificationsPermission(),
      TargetPlatform.iOS || TargetPlatform.macOS =>
        await plugin.requestDarwinNotificationsPermission(),
      _ => false,
    };
    return granted ?? false;
  }

  /// Schedules all four daily reminders.
  Future<void> scheduleAll() async {
    final now = DateTime.now();
    for (final slot in kReminderTimes) {
      await _scheduleSlot(slot, now);
    }
  }

  /// Cancels every scheduled reminder.
  Future<void> cancelAll() => plugin.cancelAll();

  /// Whether a reminder tap cold-started the app, and if so, which slot.
  ///
  /// Call this once at startup, after [initialize] — a cold start must be
  /// read explicitly because by the time anything can listen to [taps], the
  /// launch that would have fired it has already happened.
  Future<ReminderTap?> launchTap() async {
    final details = await plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return _tapFromPayload(details.notificationResponse?.payload);
  }

  Future<void> _scheduleSlot(ReminderSlot slot, DateTime now) async {
    final scheduledDate = tz.TZDateTime.from(
      nextOccurrence(slot, now: now),
      tz.local,
    );
    try {
      await _zonedSchedule(
        slot,
        scheduledDate,
        AndroidScheduleMode.exactAllowWhileIdle,
      );
    } on PlatformException {
      // The exact-alarm permission was never granted, or was revoked between
      // the last check and this call -- degrade to an inexact schedule
      // instead of losing the reminder entirely. Mirrors the Kotlin's
      // `SecurityException` catch in `ReminderScheduler.scheduleNext`.
      await _zonedSchedule(
        slot,
        scheduledDate,
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> _zonedSchedule(
    ReminderSlot slot,
    tz.TZDateTime scheduledDate,
    AndroidScheduleMode mode,
  ) => plugin.zonedSchedule(
    id: slot.id,
    title: _notificationTitle,
    body: _notificationBody,
    scheduledDate: scheduledDate,
    notificationDetails: _notificationDetails,
    androidScheduleMode: mode,
    matchDateTimeComponents: DateTimeComponents.time,
    payload: '${slot.id}',
  );

  void _handleTap(NotificationResponse response) {
    final tap = _tapFromPayload(response.payload);
    if (tap != null) _tapController.add(tap);
  }

  ReminderTap? _tapFromPayload(String? payload) {
    final slotId = payload == null ? null : int.tryParse(payload);
    return slotId == null ? null : ReminderTap(slotId);
  }

  /// The device's real time zone, e.g. `Europe/Budapest`.
  ///
  /// Using the real IANA zone — rather than a fixed UTC-offset stand-in —
  /// is what lets a reminder keep its wall-clock hour across a daylight
  /// saving change: [deviceTimeZone] reports the zone's name, and
  /// [tz.getLocation] resolves it to the `timezone` package's own copy of
  /// that zone's real transition rules, which is what
  /// `matchDateTimeComponents: DateTimeComponents.time` needs to keep
  /// computing the correct next occurrence long after today's reminders are
  /// scheduled.
  ///
  /// Falls back to UTC — rather than throwing and leaving reminders
  /// unscheduled — if the platform lookup fails or reports a name the
  /// `timezone` database doesn't recognise. Either way the device still gets
  /// its four reminders; they just land on UTC clock time instead of the
  /// device's own, exactly as they always did before this method existed.
  Future<tz.Location> _deviceLocation() async {
    final String name;
    try {
      name = await deviceTimeZone.localZoneName();
    } on PlatformException {
      return tz.UTC;
    }
    try {
      return tz.getLocation(name);
    } on tz.LocationNotFoundException {
      return tz.UTC;
    }
  }
}

NotificationDetails get _notificationDetails => const NotificationDetails(
  android: AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: _channelDescription,
    category: AndroidNotificationCategory.reminder,
    icon: 'ic_notification',
  ),
  iOS: DarwinNotificationDetails(),
);
