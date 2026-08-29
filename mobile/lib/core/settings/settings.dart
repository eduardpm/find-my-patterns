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

/// Everything this device remembers between runs.
///
/// Deliberately small: where the backend is, and how the app should look.
/// Nothing here describes the user's data — that lives on the backend.
class const AppSettings({
  final BackendAddress backend = BackendAddress.unset,
  final ThemeModeSetting themeMode = ThemeModeSetting.system,
  final JournalPalette palette = JournalPalette.defaultPalette,
}) {
  /// A copy of these settings with the given fields replaced.
  AppSettings copyWith({
    BackendAddress? backend,
    ThemeModeSetting? themeMode,
    JournalPalette? palette,
  }) => AppSettings(
    backend: backend ?? this.backend,
    themeMode: themeMode ?? this.themeMode,
    palette: palette ?? this.palette,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.backend == backend &&
      other.themeMode == themeMode &&
      other.palette == palette;

  @override
  int get hashCode => Object.hash(backend, themeMode, palette);
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
}
