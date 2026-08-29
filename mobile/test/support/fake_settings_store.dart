import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/theme/journal_palette.dart';

/// An in-memory [SettingsStore] that records what it was asked to save.
class FakeSettingsStore implements SettingsStore {
  /// Creates a store that starts from the given settings.
  FakeSettingsStore([this._settings = const AppSettings()]);

  AppSettings _settings;

  /// Every address handed to [saveBackendAddress], in order.
  final List<BackendAddress> savedAddresses = [];

  /// Every mode handed to [saveThemeMode], in order.
  final List<ThemeModeSetting> savedThemeModes = [];

  /// Every palette handed to [savePalette], in order.
  final List<JournalPalette> savedPalettes = [];

  /// Set to make [load] fail, standing in for unreadable storage.
  Object? loadError;

  @override
  Future<AppSettings> load() async {
    if (loadError case final error?) throw error;
    return _settings;
  }

  @override
  Future<void> saveBackendAddress(BackendAddress backend) async {
    savedAddresses.add(backend);
    _settings = _settings.copyWith(backend: backend);
  }

  @override
  Future<void> saveThemeMode(ThemeModeSetting mode) async {
    savedThemeModes.add(mode);
    _settings = _settings.copyWith(themeMode: mode);
  }

  @override
  Future<void> savePalette(JournalPalette palette) async {
    savedPalettes.add(palette);
    _settings = _settings.copyWith(palette: palette);
  }
}
