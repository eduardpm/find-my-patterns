import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';

/// Reads and writes whether the first-week backdating nudge ("How was
/// yesterday?" -- #36) has been dismissed on this device.
///
/// An interface rather than a singleton so tests, and any app that outgrows
/// `SharedPreferences`, can substitute their own implementation -- the same
/// shape `SettingsStore` and `ComposerDraftStore` both have.
abstract interface class BackdateNudgeStore {
  /// Whether the nudge has been dismissed.
  Future<bool> isDismissed();

  /// Marks the nudge dismissed, so it never shows again on this device.
  Future<void> dismiss();
}

/// The default [BackdateNudgeStore], backed by `SharedPreferences`.
///
/// Plain unencrypted storage is deliberate, the same way it is for
/// `SharedPreferencesComposerDraftStore`: this is a device preference about
/// whether a nudge card was dismissed, not diary content.
class SharedPreferencesBackdateNudgeStore implements BackdateNudgeStore {
  /// Creates a store that writes a key prefixed with [prefix].
  const SharedPreferencesBackdateNudgeStore({
    this.prefix = AppConfig.storagePrefix,
  });

  /// The prefix applied to the key this store touches.
  final String prefix;

  String get _key => '$prefix.backdate_nudge_dismissed';

  @override
  Future<bool> isDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  @override
  Future<void> dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
