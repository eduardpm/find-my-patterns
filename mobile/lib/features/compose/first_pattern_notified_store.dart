import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';

/// Reads and writes whether the first-pattern celebration (L-3/#38) has
/// already fired once on this device -- inline, as a notification, or as a
/// cold-start launch tap; this store does not distinguish which.
///
/// The whole point of this flag is exactly-once semantics: the first
/// pattern the diary ever surfaces is a one-time "aha" moment, not a
/// recurring nudge like a reminder, so once it has fired -- however it
/// fired -- `EntryComposerController._checkFirstPattern` must never fire
/// it again for the life of this diary.
///
/// An interface rather than a singleton, the same shape `BackdateNudgeStore`
/// and `ComposerDraftStore` both have: tests substitute an in-memory fake
/// instead of a real `SharedPreferences` instance, and any app that
/// outgrows `SharedPreferences` can substitute its own implementation
/// without EntryComposerController` changing at all.
abstract interface class FirstPatternNotifiedStore {
  /// Whether the celebration has already fired.
  Future<bool> hasNotified();

  /// Marks the celebration fired, so it never fires again on this device.
  Future<void> markNotified();
}

/// The default [FirstPatternNotifiedStore], backed by `SharedPreferences`.
///
/// Plain unencrypted storage is deliberate, the same way it is for
/// `SharedPreferencesBackdateNudgeStore`: this is a device preference
/// recording that a one-time notification already fired, not diary
/// content.
class SharedPreferencesFirstPatternNotifiedStore
    implements FirstPatternNotifiedStore {
  /// Creates a store that writes a key prefixed with [prefix].
  const SharedPreferencesFirstPatternNotifiedStore({
    this.prefix = AppConfig.storagePrefix,
  });

  /// The prefix applied to the key this store touches.
  final String prefix;

  String get _key => '$prefix.first_pattern_notified';

  @override
  Future<bool> hasNotified() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  @override
  Future<void> markNotified() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
