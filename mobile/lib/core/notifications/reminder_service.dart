import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'device_time_zone.dart';
import 'notifications_plugin.dart';
import 'reminder_schedule.dart';

/// A local notification the user tapped, cold or warm -- routed to whatever
/// that particular notification means to open.
///
/// A sealed supertype rather than one payload-agnostic class: [ReminderTap]
/// and [FirstPatternTap] (#38) go to different places -- the composer and
/// Insights respectively -- and `flutter_local_notifications`'
/// `FlutterLocalNotificationsPlugin.initialize` takes exactly one `onTap`
/// callback for the whole app, so every kind of tap this app can receive
/// has to funnel through the same [ReminderService] and come back out
/// distinguishable. See [ReminderService._tapFromPayload] for how the
/// payload string decides which one a given tap becomes.
sealed class NotificationTap {
  const NotificationTap();
}

/// A reminder notification the user tapped, cold or warm.
///
/// Carries [slotId] rather than a [ReminderSlot] itself: the tap is
/// identified from the notification payload the plugin hands back, which is
/// a bare string, and nothing downstream of a tap needs the hour and minute
/// back — every reminder opens the same composer regardless of which slot
/// fired it.
final class const ReminderTap(final int slotId) extends NotificationTap {
  @override
  bool operator ==(Object other) =>
      other is ReminderTap && other.slotId == slotId;

  @override
  int get hashCode => slotId.hashCode;

  @override
  String toString() => 'ReminderTap($slotId)';
}

/// A tap on the first-pattern celebration notification (#38) -- opens
/// Insights rather than the composer.
///
/// Carries nothing: there is only ever one first-pattern notification for
/// the life of a diary (`EntryComposerController._checkFirstPattern`
/// enforces the exactly-once flag), so there is no id or slot to
/// distinguish one from another the way [ReminderTap.slotId] has to.
final class const FirstPatternTap() extends NotificationTap {
  @override
  bool operator ==(Object other) => other is FirstPatternTap;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'FirstPatternTap()';
}

/// The channel and notification the user's reminders are shown under.
///
/// Originally ported from `ReminderNotifier` (Kotlin) and
/// `android/app/src/main/res/values/strings.xml`, back when every device got
/// the same four fixed times. The copy is deliberately deterministic —
/// never randomised or personalised — so what fires is exactly what the
/// unit tests and this constant say it is.
const String _channelId = 'diary_reminders';
const String _channelName = 'Diary check-ins';
const String _channelDescription =
    'Reminders to log a diary entry at the times you choose in Settings.';
const String _notificationTitle = 'A moment for your diary';
const String _notificationBody = 'What happened since your last entry?';

/// The payload `showFirstPatternNotification` sends, and the sentinel
/// `_tapFromPayload` checks for before trying [int.tryParse] on a reminder
/// slot id.
///
/// Deliberately not numeric -- a reminder's payload is always a bare
/// integer (`'${slot.id}'`), so a non-numeric sentinel can never collide
/// with one no matter which slot ids a device has scheduled, and existing
/// scheduled reminders (whose payload was baked in before this feature
/// existed) keep decoding exactly as before.
const String _firstPatternPayload = 'first_pattern';

/// The notification id `showFirstPatternNotification` shows under.
///
/// `ReminderSlot.id` ranges over `0..1439` (`hour * 60 + minute`); a
/// negative id can never collide with, and so can never silently replace
/// or be replaced by, a scheduled reminder.
const int _firstPatternNotificationId = -1;

/// Schedules and reacts to the user's configured check-in reminders.
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
///
/// The Kotlin app fixed every device to the same four slots; this service
/// takes whichever slots the caller passes to [scheduleAll], which is how
/// `RemindersController` (`core/notifications/reminder_settings_controller.dart`)
/// drives it from the user's own choices in Settings.
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

  final StreamController<NotificationTap> _tapController =
      StreamController<NotificationTap>.broadcast();

  /// Emits a [NotificationTap] each time the user taps a notification from
  /// this app while the app is already running -- a [ReminderTap] or a
  /// [FirstPatternTap] (#38), broadcast on the same stream because both
  /// come back through the one `onTap` callback [initialize] registers.
  /// `reminder_providers.dart`'s `OpenComposerSignal` and
  /// `OpenInsightsSignal` each filter this down to the one kind they care
  /// about.
  ///
  /// A cold start is not reported here — read it once from [launchTap]
  /// instead, since by the time this stream has a listener the launch
  /// notification response has already happened.
  Stream<NotificationTap> get taps => _tapController.stream;

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
  ///
  /// Call this when the user turns a reminder on, not unconditionally at
  /// startup — the Android 13+ system dialog it can trigger should appear
  /// because the user just asked for a reminder, not on every cold start
  /// regardless of whether any reminder is even enabled. Once the platform
  /// has already answered, calling again is safe: Android returns the known
  /// answer without showing the dialog a second time. To check the current
  /// answer without any risk of a prompt, use [notificationsEnabled].
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

  /// Whether this app can currently post notifications, without prompting.
  ///
  /// `true` on any platform other than Android, where there is no equivalent
  /// read-only check and [requestPermission] is the only signal this
  /// service has — mirroring how [requestPermission] itself treats those
  /// platforms.
  Future<bool> notificationsEnabled() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    return await plugin.areNotificationsEnabled() ?? true;
  }

  /// Opens the OS notification-settings screen for this app, for a "grant in
  /// system settings" link shown once [notificationsEnabled] is `false`.
  ///
  /// Returns whether it could be opened. `false` on any platform other than
  /// Android, where there is nothing to open.
  Future<bool> openNotificationSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return await plugin.openNotificationSettings() ?? false;
  }

  /// Schedules every slot in [slots], cancelling nothing first.
  ///
  /// The caller decides which slots that is — usually the user's currently
  /// enabled reminders — and is responsible for calling [cancelAll] first
  /// when the set of slots has changed, so a removed or disabled reminder's
  /// old alarm doesn't linger.
  Future<void> scheduleAll({required List<ReminderSlot> slots}) async {
    final now = DateTime.now();
    for (final slot in slots) {
      await _scheduleSlot(slot, now);
    }
  }

  /// Cancels every scheduled reminder.
  Future<void> cancelAll() => plugin.cancelAll();

  /// Shows the first-pattern celebration (#38) immediately, under the same
  /// channel and permission handling as a reminder.
  ///
  /// [title] and [body] are the caller's own -- this service holds no
  /// first-pattern copy of its own, the same way it holds no diary
  /// vocabulary at all; `EntryComposerController._checkFirstPattern`
  /// derives them from the pattern's own evidence count before calling
  /// this, via `first_pattern_copy.dart`.
  Future<void> showFirstPatternNotification({
    required String title,
    required String body,
  }) => plugin.show(
    id: _firstPatternNotificationId,
    title: title,
    body: body,
    notificationDetails: _notificationDetails,
    payload: _firstPatternPayload,
  );

  /// Whether a notification tap cold-started the app, and if so, which one.
  ///
  /// Call this once at startup, after [initialize] — a cold start must be
  /// read explicitly because by the time anything can listen to [taps], the
  /// launch that would have fired it has already happened.
  Future<NotificationTap?> launchTap() async {
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

  /// Resolves a plugin payload to the [NotificationTap] it identifies, or
  /// `null` for a payload this service does not recognise -- an unparsable
  /// payload is silently dropped rather than guessed at, the same way it
  /// always has been for a reminder.
  ///
  /// [_firstPatternPayload] is checked first, before [int.tryParse]: it is
  /// not numeric, so there is no ambiguity between the two branches, but
  /// checking it first keeps this reading as "first, the one fixed
  /// sentinel; otherwise, a slot id" rather than relying on the parse
  /// failing to fall through correctly.
  NotificationTap? _tapFromPayload(String? payload) {
    if (payload == null) return null;
    if (payload == _firstPatternPayload) return const FirstPatternTap();
    final slotId = int.tryParse(payload);
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
