import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings.dart';
import '../settings/settings_controller.dart';
import 'digest_schedule.dart';
import 'reminder_providers.dart';

/// Orchestrates the Digest card's writes (R-2): persists the user's choice,
/// asks for the platform permission the first time it is needed, and keeps
/// the scheduled alarm in step with whether the digest is on.
///
/// Mirrors `RemindersController` in `reminder_settings_controller.dart`
/// exactly, one toggle instead of a list: the state is whether the platform
/// is currently blocking notifications, watched directly by the Digest
/// card for its own "grant in system settings" note.
class DigestSettingsController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    // `ref.read`, not `ref.watch` — see `RemindersController.build`'s own
    // doc comment for why: `save` already refreshes this state as part of
    // the same write, and watching `settingsProvider` here would make that
    // write re-trigger this build with a second, independent answer.
    final settings = await ref.read(settingsProvider.future);
    if (!settings.digest.enabled) return false;
    final enabled = await ref
        .read(reminderServiceProvider)
        .notificationsEnabled();
    return !enabled;
  }

  /// Persists [schedule], requests the platform permission if this save
  /// turns the digest on, and (re)arms or cancels the scheduled alarm to
  /// match.
  Future<void> save(DigestTime schedule) async {
    var blocked = false;
    if (schedule.enabled) {
      final granted = await ref
          .read(reminderServiceProvider)
          .requestPermission();
      blocked = !granted;
    }
    await ref.read(settingsProvider.notifier).saveDigestSchedule(schedule);
    await rearm();
    state = AsyncData(blocked);
  }

  /// Re-arms the digest alarm from whatever is currently saved, or cancels
  /// it if the digest is off.
  ///
  /// Exposed (not private) so `RemindersController._reschedule`
  /// (`reminder_settings_controller.dart`) can call it after a reminders
  /// save: that save cancels *every* scheduled notification first
  /// (`ReminderService.cancelAll`, the only cancellation
  /// `flutter_local_notifications` gives this app), and the digest alarm —
  /// scheduled independently, under its own id — would otherwise stay
  /// cancelled until the app's next cold start re-arms it
  /// (`app.dart#_restore`). Calling this immediately after closes that gap
  /// instead of leaving the user without a digest notification for however
  /// long it takes them to relaunch the app.
  Future<void> rearm() async {
    final settings = await ref.read(settingsProvider.future);
    final schedule = settings.digest;
    final service = ref.read(reminderServiceProvider);
    if (schedule.enabled) {
      await service.scheduleDigest(
        DigestSlot(schedule.weekday, schedule.hour, schedule.minute),
      );
    } else {
      await service.cancelDigest();
    }
  }

  /// Opens the OS notification-settings screen, for the denial note's
  /// "grant in system settings" link.
  Future<void> openSystemSettings() =>
      ref.read(reminderServiceProvider).openNotificationSettings();
}

/// The controller the Digest card reads and writes through.
final digestSettingsControllerProvider =
    AsyncNotifierProvider<DigestSettingsController, bool>(
      DigestSettingsController.new,
    );
