import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/network_providers.dart';
import '../theme/journal_palette.dart';
import 'settings.dart';

/// The store the app reads and writes its settings through.
///
/// Overridable so tests, and any app that needs encrypted or synced storage,
/// can substitute an implementation without touching the screens.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => const SharedPreferencesSettingsStore(),
);

/// The app's settings, loaded once from disk and updated as the user changes
/// them.
///
/// Every backend-address change is pushed into the HTTP core in the same step,
/// so the client can never be pointed at a server the user has moved away from.
class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.watch(settingsStoreProvider).load();

  /// Validates and saves user-typed server details.
  ///
  /// Returns the validation result so the caller can show the reason a bad
  /// address was refused. Nothing is written and the HTTP core is left alone
  /// unless the details are accepted.
  Future<BackendAddressResult> saveBackendAddress({
    required String rawHost,
    required String rawPort,
    BackendScheme scheme = BackendScheme.http,
  }) async {
    final result = BackendAddress.parse(
      rawHost: rawHost,
      rawPort: rawPort,
      scheme: scheme,
    );
    if (result case BackendAddressAccepted(:final address)) {
      await ref.read(settingsStoreProvider).saveBackendAddress(address);
      ref.read(apiClientProvider).configure(address);
      state = AsyncData(_current.copyWith(backend: address));
    }
    return result;
  }

  /// Saves [mode] as the appearance preference.
  Future<void> saveThemeMode(ThemeModeSetting mode) async {
    await ref.read(settingsStoreProvider).saveThemeMode(mode);
    state = AsyncData(_current.copyWith(themeMode: mode));
  }

  /// Saves [palette] as the chosen paper.
  Future<void> savePalette(JournalPalette palette) async {
    await ref.read(settingsStoreProvider).savePalette(palette);
    state = AsyncData(_current.copyWith(palette: palette));
  }

  /// Saves [reminders] as the full set of configured reminders.
  ///
  /// Persistence only — requesting the notification permission and
  /// (re)scheduling the enabled slots is `RemindersController`'s job
  /// (`core/notifications/reminder_settings_controller.dart`), which calls
  /// this as one step of a save rather than duplicating the write here.
  Future<void> saveReminders(List<ReminderTime> reminders) async {
    await ref.read(settingsStoreProvider).saveReminders(reminders);
    state = AsyncData(_current.copyWith(reminders: reminders));
  }

  /// Saves [schedule] as the weekly digest's day, time and on/off state
  /// (R-2).
  ///
  /// Persistence only, the same split [saveReminders] draws with
  /// `RemindersController` — requesting the notification permission and
  /// (re)scheduling the alarm is `DigestSettingsController`'s job
  /// (`core/notifications/digest_settings_controller.dart`).
  Future<void> saveDigestSchedule(DigestTime schedule) async {
    await ref.read(settingsStoreProvider).saveDigestSchedule(schedule);
    state = AsyncData(_current.copyWith(digest: schedule));
  }

  AppSettings get _current => state.value ?? const AppSettings();
}

/// The app's settings.
final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
