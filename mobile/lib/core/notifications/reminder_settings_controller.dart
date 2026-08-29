import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings.dart';
import '../settings/settings_controller.dart';
import 'digest_settings_controller.dart';
import 'reminder_providers.dart';
import 'reminder_schedule.dart';

/// Orchestrates the Reminders card's writes: persists the user's choice,
/// asks for the platform permission the first time it is needed, and keeps
/// the scheduled alarms in step with which reminders are enabled.
///
/// The state is whether the platform is currently blocking notifications —
/// `true` once the user has an enabled reminder and the platform said no,
/// `false` otherwise (nothing enabled yet, or permission granted). The
/// Reminders card watches this directly to show its "grant in system
/// settings" note, rather than each save call returning a one-off result
/// that a widget would have to squirrel away in its own state to survive a
/// rebuild.
class RemindersController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    // `ref.read`, not `ref.watch`: this only has to answer once, the first
    // time the Reminders card is shown. `save` is this provider's only other
    // writer, and it already calls `SettingsController.saveReminders` as
    // part of the same save -- watching `settingsProvider` would make that
    // write re-trigger this build, clobbering the freshly computed `blocked`
    // state `save` is about to set with a second, independent answer from
    // [ReminderService.notificationsEnabled].
    final settings = await ref.read(settingsProvider.future);
    if (!settings.reminders.any((reminder) => reminder.enabled)) {
      return false;
    }
    // A read-only check, never a prompt: a returning user whose reminder is
    // already enabled must see an accurate note without the OS asking them
    // again just because they opened Settings.
    final enabled = await ref
        .read(reminderServiceProvider)
        .notificationsEnabled();
    return !enabled;
  }

  /// Persists [reminders] as the full set, requests the platform permission
  /// if this save leaves at least one reminder enabled, and reschedules
  /// every enabled slot.
  ///
  /// Requesting permission on every such save rather than only the very
  /// first one is safe, not redundant: once the platform has answered,
  /// asking again never shows the dialog a second time (see
  /// `ReminderService.requestPermission`) — it just refreshes this
  /// controller's view of the current answer, which is what keeps the
  /// denial note accurate if the user grants it from system settings
  /// mid-session and comes back.
  Future<void> save(List<ReminderTime> reminders) async {
    final anyEnabled = reminders.any((reminder) => reminder.enabled);
    var blocked = false;
    if (anyEnabled) {
      final granted = await ref
          .read(reminderServiceProvider)
          .requestPermission();
      blocked = !granted;
    }
    await ref.read(settingsProvider.notifier).saveReminders(reminders);
    await _reschedule(reminders);
    state = AsyncData(blocked);
  }

  /// Opens the OS notification-settings screen, for the denial note's
  /// "grant in system settings" link.
  Future<void> openSystemSettings() =>
      ref.read(reminderServiceProvider).openNotificationSettings();

  Future<void> _reschedule(List<ReminderTime> reminders) async {
    final service = ref.read(reminderServiceProvider);
    final slots = [
      for (final reminder in reminders)
        if (reminder.enabled) ReminderSlot(reminder.hour, reminder.minute),
    ];
    // Every reschedule starts from a clean slate: a reminder that was just
    // disabled, removed, or moved to a new time must not leave its old
    // alarm still armed under an id nothing here tracks any more.
    await service.cancelAll();
    if (slots.isNotEmpty) {
      await service.scheduleAll(slots: slots);
    }
    // R-2: `cancelAll` above is `flutter_local_notifications`' only
    // cancellation broad enough to guarantee a removed reminder's alarm is
    // really gone (see the comment above it) — but it cancels *every*
    // scheduled notification, including the weekly digest, which is armed
    // independently of this reminder list under its own id. Re-arming it
    // here immediately closes that gap; without this call the digest would
    // stay silently cancelled until the app's next cold start
    // (`app.dart#_restore` re-arms it too, but only then).
    await ref.read(digestSettingsControllerProvider.notifier).rearm();
  }
}

/// The controller the Reminders card reads and writes through.
final remindersControllerProvider =
    AsyncNotifierProvider<RemindersController, bool>(RemindersController.new);
