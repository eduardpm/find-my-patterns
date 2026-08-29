import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../theme/journal_palette.dart';

/// The transport used to reach the backend.
///
/// Stored as a stable id rather than an enum index or name: an id changes only
/// when someone changes it on purpose, and an unrecognised one falls back to
/// the default instead of refusing to load.
enum BackendScheme {
  /// Plain HTTP, the default for a backend on your own network.
  http('http', 'HTTP'),

  /// HTTPS, for a backend behind a TLS-terminating reverse proxy.
  https('https', 'HTTPS');

  const BackendScheme(this.id, this.label);

  /// The value written to device storage and used in a URL.
  final String id;

  /// The human-readable name shown in Settings.
  final String label;

  /// The scheme with the given [id], or [BackendScheme.http] if unrecognised.
  static BackendScheme fromId(String? id) =>
      BackendScheme.values.where((v) => v.id == id).firstOrNull ??
      BackendScheme.http;
}

/// Where this app's backend lives.
///
/// Typed in once on the Settings screen and persisted; every request goes to
/// [origin]. Construct validated instances with [BackendAddress.parse] rather
/// than trusting raw user input.
class const BackendAddress({
  final BackendScheme scheme = BackendScheme.http,
  final String host = '',
  final int port = AppConfig.defaultPort,
}) {
  /// The address meaning "the user has not configured a server yet".
  static const BackendAddress unset = BackendAddress();

  /// The lowest port number a server can listen on.
  static const int minPort = 1;

  /// The highest port number a server can listen on.
  static const int maxPort = 65535;

  /// Whether this address is complete enough to send a request to.
  bool get isConfigured => host.isNotEmpty;

  /// The scheme, host and port joined into a URL origin.
  String get origin => '${scheme.id}://$host:$port';

  /// Validates user-typed server details.
  ///
  /// [rawHost] may be pasted with a scheme, a trailing slash or surrounding
  /// whitespace; all three are cleaned up, and a pasted `https://` prefix wins
  /// over [scheme] so that pasting a full URL does the obvious thing. [rawPort]
  /// must parse to a number within [minPort]..[maxPort], or the whole address is
  /// rejected — a typo must never silently become the default port.
  static BackendAddressResult parse({
    required String rawHost,
    required String rawPort,
    BackendScheme scheme = BackendScheme.http,
  }) {
    var host = rawHost.trim();
    var resolvedScheme = scheme;

    for (final candidate in BackendScheme.values) {
      final prefix = '${candidate.id}://';
      if (host.toLowerCase().startsWith(prefix)) {
        resolvedScheme = candidate;
        host = host.substring(prefix.length);
        break;
      }
    }
    host = host.replaceAll(RegExp(r'/+$'), '').trim();

    if (host.isEmpty) {
      return const BackendAddressRejected(
        'Enter a host — for example 192.168.1.20 or 10.0.2.2.',
      );
    }
    if (RegExp(r'\s').hasMatch(host)) {
      return const BackendAddressRejected('A host cannot contain spaces.');
    }

    final trimmedPort = rawPort.trim();
    final port = int.tryParse(trimmedPort);
    if (port == null) {
      return BackendAddressRejected('"$trimmedPort" is not a port number.');
    }
    if (port < minPort || port > maxPort) {
      return const BackendAddressRejected(
        'A port must be between $minPort and $maxPort.',
      );
    }

    return BackendAddressAccepted(
      BackendAddress(scheme: resolvedScheme, host: host, port: port),
    );
  }

  /// A copy of this address with the given fields replaced.
  BackendAddress copyWith({
    BackendScheme? scheme,
    String? host,
    int? port,
  }) => BackendAddress(
    scheme: scheme ?? this.scheme,
    host: host ?? this.host,
    port: port ?? this.port,
  );

  @override
  bool operator ==(Object other) =>
      other is BackendAddress &&
      other.scheme == scheme &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(scheme, host, port);

  @override
  String toString() => origin;
}

/// The outcome of validating user-typed server details.
///
/// Sealed so that a caller switching on the result cannot forget a case.
sealed class const BackendAddressResult();

/// The details were valid and produced [address].
final class const BackendAddressAccepted(final BackendAddress address)
    extends BackendAddressResult;

/// The details were rejected; [message] explains why, in the user's terms.
final class const BackendAddressRejected(final String message)
    extends BackendAddressResult;

/// Light or dark preference, stored as a stable id. See [BackendScheme] for why.
enum ThemeModeSetting {
  /// Follow the operating system's setting.
  system('system', 'System'),

  /// Always use the light theme.
  light('light', 'Light'),

  /// Always use the dark theme.
  dark('dark', 'Dark');

  const ThemeModeSetting(this.id, this.label);

  /// The value written to device storage.
  final String id;

  /// The human-readable name shown in Settings.
  final String label;

  /// The setting with the given [id], or [ThemeModeSetting.system] if
  /// unrecognised.
  static ThemeModeSetting fromId(String? id) =>
      ThemeModeSetting.values.where((v) => v.id == id).firstOrNull ??
      ThemeModeSetting.system;
}

/// One reminder the user has configured: a wall-clock time, and whether it
/// is currently armed.
///
/// A settings-layer value. [enabled] is what only Settings and the
/// Reminders card need to know; the schedule computation in
/// `core/notifications/reminder_schedule.dart` only ever sees the bare
/// hour and minute, as a `ReminderSlot` built from an enabled entry at the
/// one call site that schedules it — which is why that type stays free of
/// an `enabled` flag it would otherwise carry for no reason of its own.
class const ReminderTime({
  required final int hour,
  required final int minute,
  final bool enabled = false,
}) {
  /// The most reminders the Reminders card lets a user keep at once.
  static const int maxCount = 6;

  /// A copy of this reminder with the given fields replaced.
  ReminderTime copyWith({int? hour, int? minute, bool? enabled}) =>
      ReminderTime(
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      other is ReminderTime &&
      other.hour == hour &&
      other.minute == minute &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(hour, minute, enabled);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}'
      '${enabled ? ' (on)' : ' (off)'}';
}

/// The reminders a fresh install starts with: a morning and an evening
/// suggestion, both off until the user turns one on.
///
/// Echoes two of the old Kotlin app's four fixed slots rather than reviving
/// all four — a user who wants more adds them from the Reminders card, up
/// to [ReminderTime.maxCount].
const List<ReminderTime> kDefaultReminders = [
  ReminderTime(hour: 9, minute: 0),
  ReminderTime(hour: 21, minute: 0),
];

/// [R-2] The weekly digest's schedule: a day of the week, a wall-clock time,
/// and whether it is currently armed.
///
/// The settings-layer twin of `core/notifications/digest_schedule.dart`'s
/// `DigestSlot`, the same split [ReminderTime]/`ReminderSlot` already draw:
/// [enabled] is what only Settings and the Digest card need to know, and the
/// schedule computation only ever sees the bare weekday, hour and minute, as
/// a `DigestSlot` built from this at the one call site that schedules it.
///
/// [weekday] uses [DateTime]'s convention (`1`..`7`, Monday first) — see
/// `DigestSlot`'s own doc comment for why.
class const DigestTime({
  required final int weekday,
  required final int hour,
  required final int minute,
  final bool enabled = false,
}) {
  /// A copy of this schedule with the given fields replaced.
  DigestTime copyWith({int? weekday, int? hour, int? minute, bool? enabled}) =>
      DigestTime(
        weekday: weekday ?? this.weekday,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      other is DigestTime &&
      other.weekday == weekday &&
      other.hour == hour &&
      other.minute == minute &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(weekday, hour, minute, enabled);

  @override
  String toString() =>
      'DigestTime(weekday: $weekday, $hour:'
      '${minute.toString().padLeft(2, '0')}'
      '${enabled ? ', on' : ', off'})';
}

/// The digest schedule a fresh install starts with: Sunday at 18:00, off
/// until the user turns it on (issue #42's own default).
const DigestTime kDefaultDigestSchedule = DigestTime(
  weekday: DateTime.sunday,
  hour: 18,
  minute: 0,
);

/// Everything this device remembers between runs.
///
/// Where the backend is, how the app should look, and when it should remind
/// the user to write — device configuration the user chose, never diary
/// content. Nothing here describes the user's data — that lives on the
/// backend.
class const AppSettings({
  final BackendAddress backend = BackendAddress.unset,
  final ThemeModeSetting themeMode = ThemeModeSetting.system,
  final JournalPalette palette = JournalPalette.defaultPalette,
  final List<ReminderTime> reminders = kDefaultReminders,

  /// R-2's weekly digest schedule. Singular, unlike [reminders] — there is
  /// one toggle and one day/time, not a user-managed list.
  final DigestTime digest = kDefaultDigestSchedule,
}) {
  /// A copy of these settings with the given fields replaced.
  AppSettings copyWith({
    BackendAddress? backend,
    ThemeModeSetting? themeMode,
    JournalPalette? palette,
    List<ReminderTime>? reminders,
    DigestTime? digest,
  }) => AppSettings(
    backend: backend ?? this.backend,
    themeMode: themeMode ?? this.themeMode,
    palette: palette ?? this.palette,
    reminders: reminders ?? this.reminders,
    digest: digest ?? this.digest,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.backend == backend &&
      other.themeMode == themeMode &&
      other.palette == palette &&
      listEquals(other.reminders, reminders) &&
      other.digest == digest;

  @override
  int get hashCode => Object.hash(
    backend,
    themeMode,
    palette,
    Object.hashAll(reminders),
    digest,
  );
}

/// Reads and writes [AppSettings].
///
/// An interface rather than a singleton so tests, and any app that outgrows
/// `SharedPreferences`, can substitute their own implementation through
/// `settingsStoreProvider`.
abstract interface class SettingsStore {
  /// Reads the stored settings, falling back to defaults for anything absent.
  Future<AppSettings> load();

  /// Persists [backend] as the address every later request should use.
  Future<void> saveBackendAddress(BackendAddress backend);

  /// Persists [mode] as the appearance preference.
  Future<void> saveThemeMode(ThemeModeSetting mode);

  /// Persists [palette] as the chosen paper.
  Future<void> savePalette(JournalPalette palette);

  /// Persists [reminders] as the full set of configured reminders,
  /// replacing whatever was stored before.
  ///
  /// Takes the whole list rather than one changed entry: the Reminders card
  /// always has the complete set in hand already (it renders every row from
  /// it), and a whole-list write is what lets removing a reminder persist
  /// as an empty list rather than needing a separate delete operation.
  Future<void> saveReminders(List<ReminderTime> reminders);

  /// Persists [schedule] as the digest's day, time and on/off state (R-2),
  /// replacing whatever was stored before. Singular, like [saveThemeMode] and
  /// [savePalette] — there is one digest schedule, not a list to add to or
  /// remove from the way [saveReminders] manages.
  Future<void> saveDigestSchedule(DigestTime schedule);
}

/// The default [SettingsStore], backed by `SharedPreferences`.
///
/// Plain unencrypted storage is deliberate: none of these three values is
/// sensitive. A session cookie, which is, lives in the cookie jar instead.
class SharedPreferencesSettingsStore implements SettingsStore {
  /// Creates a store that writes keys prefixed with [prefix].
  const SharedPreferencesSettingsStore({
    this.prefix = AppConfig.storagePrefix,
  });

  /// The prefix applied to every key this store touches.
  final String prefix;

  String get _schemeKey => '$prefix.backend_scheme';
  String get _hostKey => '$prefix.backend_host';
  String get _portKey => '$prefix.backend_port';
  String get _themeKey => '$prefix.theme_mode';
  String get _paletteKey => '$prefix.appearance_palette';
  String get _remindersKey => '$prefix.reminders';
  String get _digestKey => '$prefix.digest';

  @override
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      backend: BackendAddress(
        scheme: BackendScheme.fromId(prefs.getString(_schemeKey)),
        host: prefs.getString(_hostKey) ?? '',
        port: prefs.getInt(_portKey) ?? AppConfig.defaultPort,
      ),
      themeMode: ThemeModeSetting.fromId(prefs.getString(_themeKey)),
      palette: JournalPalette.fromId(prefs.getString(_paletteKey)),
      reminders: _decodeReminders(prefs.getString(_remindersKey)),
      digest: _decodeDigestSchedule(prefs.getString(_digestKey)),
    );
  }

  @override
  Future<void> saveBackendAddress(BackendAddress backend) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_schemeKey, backend.scheme.id);
    await prefs.setString(_hostKey, backend.host);
    await prefs.setInt(_portKey, backend.port);
  }

  @override
  Future<void> saveThemeMode(ThemeModeSetting mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.id);
  }

  @override
  Future<void> savePalette(JournalPalette palette) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paletteKey, palette.id);
  }

  @override
  Future<void> saveReminders(List<ReminderTime> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_remindersKey, _encodeReminders(reminders));
  }

  @override
  Future<void> saveDigestSchedule(DigestTime schedule) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_digestKey, _encodeDigestSchedule(schedule));
  }

  String _encodeDigestSchedule(DigestTime schedule) => jsonEncode({
    'weekday': schedule.weekday,
    'hour': schedule.hour,
    'minute': schedule.minute,
    'enabled': schedule.enabled,
  });

  /// Decodes a stored digest schedule, or falls back to
  /// [kDefaultDigestSchedule] — for [raw] being `null` (nothing saved yet, a
  /// fresh install) or unreadable JSON, the same two cases
  /// [_decodeReminders] falls back for.
  DigestTime _decodeDigestSchedule(String? raw) {
    if (raw == null) return kDefaultDigestSchedule;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return kDefaultDigestSchedule;
      return DigestTime(
        weekday: (decoded['weekday'] as num?)?.toInt() ?? DateTime.sunday,
        hour: (decoded['hour'] as num?)?.toInt() ?? 18,
        minute: (decoded['minute'] as num?)?.toInt() ?? 0,
        enabled: decoded['enabled'] as bool? ?? false,
      );
    } on FormatException {
      return kDefaultDigestSchedule;
    }
  }

  String _encodeReminders(List<ReminderTime> reminders) => jsonEncode([
    for (final reminder in reminders)
      {
        'hour': reminder.hour,
        'minute': reminder.minute,
        'enabled': reminder.enabled,
      },
  ]);

  /// Decodes a stored reminder list, or falls back to [kDefaultReminders].
  ///
  /// The fallback only fires for [raw] being `null` — nothing has ever been
  /// saved under this key, i.e. a fresh install — or genuinely unreadable
  /// JSON. A user who removes every reminder saves an empty list, which
  /// [jsonDecode] reads back as `[]`: a real, deliberate value that must
  /// stay empty, never spring back to the two suggestions on the next
  /// restart.
  List<ReminderTime> _decodeReminders(String? raw) {
    if (raw == null) return kDefaultReminders;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return kDefaultReminders;
      return [
        for (final entry in decoded)
          if (entry is Map)
            ReminderTime(
              hour: (entry['hour'] as num?)?.toInt() ?? 0,
              minute: (entry['minute'] as num?)?.toInt() ?? 0,
              enabled: entry['enabled'] as bool? ?? false,
            ),
      ];
    } on FormatException {
      return kDefaultReminders;
    }
  }
}
