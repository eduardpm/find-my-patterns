import 'package:find_my_patterns/core/notifications/device_time_zone.dart';
import 'package:flutter/services.dart';

/// An in-memory `DeviceTimeZone` double that answers with a fixed zone name,
/// or throws a scripted [PlatformException] once, so a test never touches a
/// real platform channel.
class FakeDeviceTimeZone implements DeviceTimeZone {
  FakeDeviceTimeZone([this.name = 'Europe/Budapest']);

  /// The zone name the next successful call answers with.
  String name;

  /// Set to make the next `localZoneName` call throw, standing in for the
  /// platform lookup failing.
  PlatformException? nextError;

  @override
  Future<String> localZoneName() async {
    if (nextError case final error?) {
      nextError = null;
      throw error;
    }
    return name;
  }
}
