import 'package:flutter_timezone/flutter_timezone.dart';

/// Resolves the device's real IANA time zone name — e.g. `Europe/Budapest`.
///
/// A narrow interface over `flutter_timezone`'s one call `ReminderService`
/// needs, the same shape as `NotificationsPlugin` and for the same reason:
/// a test can supply a fixed zone name and never touch a platform channel.
abstract interface class DeviceTimeZone {
  /// The device's current IANA zone identifier, as the platform reports it.
  Future<String> localZoneName();
}

/// The real [DeviceTimeZone], backed by `flutter_timezone`.
///
/// Holds no state of its own, so this stays a plain `const` adapter — the
/// same reasoning as `DefaultNotificationsPlugin`.
class const FlutterDeviceTimeZone() implements DeviceTimeZone {
  @override
  Future<String> localZoneName() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;
}
