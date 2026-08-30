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
  /// The tail of every `save` call issued so far, chained one after another.
  ///
  /// `reminders_card.dart` fires every mutation through
  /// `unawaited(controller.save(...))`, so a second tap can call [save]
  /// while the first call's body -- persist, then reconcile the plugin --
  /// is still awaiting a step of it. Left alone, two such calls run their
  /// cancel-then-schedule pairs concurrently and can interleave: one call's
  /// `scheduleAll` landing after the other's cancel, arming an alarm neither
  /// call's own final state wanted (#153). Chaining each [save] after
  /// whichever is already in flight keeps every call's body running start
  /// to finish before the next one begins, so calls apply in the order they
  /// were made instead of racing.
  Future<void> _saveChain = Future<void>.value();

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
  ///
  /// Chained onto [_saveChain] rather than run directly -- see that field's
  /// own doc comment for why a caller that fires this without awaiting it
  /// (`reminders_card.dart`'s `unawaited(controller.save(...))`) needs that
  /// serialisation.
  Future<void> save(List<ReminderTime> reminders) {
    final chained = _saveChain
        // Swallow a previous call's failure here, in the link used only for
        // sequencing -- an earlier save throwing must not stop every save
        // after it from ever running. The failure itself still reaches that
        // earlier call's own caller through the future `save` returned for
        // it, below.
        .catchError((_) {})
        .then((_) => _save(reminders));
    _saveChain = chained;
    return chained;
  }

  Future<void> _save(List<ReminderTime> reminders) async {
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
    // Reconciles against whatever the platform actually has armed, rather
    // than cancelling everything and rescheduling from scratch (#153): a
    // reminder that was just disabled, removed, or moved to a new time must
    // not leave its old alarm armed under an id nothing here tracks any
    // more, and neither must an alarm that leaked from some earlier save --
    // `ReminderService.reconcileReminders`'s own doc comment covers why a
    // blunt `cancelAll` here can't make that second guarantee the way this
    // can.
    await service.reconcileReminders(slots: slots);
    // Refreshes the digest alarm from current settings after every
    // reminders save, independently of what `reconcileReminders` above just
    // did to the reminder alarms -- it deliberately never touches the
    // digest's own id, so this call no longer exists to repair collateral
    // damage from a blunt `cancelAll` the way it did before. It stays as a
    // harmless, idempotent re-affirmation of the digest's own state; see
    // `DigestSettingsController.rearm`'s own doc comment for what it does.
    await ref.read(digestSettingsControllerProvider.notifier).rearm();
  }
}

/// The controller the Reminders card reads and writes through.
final remindersControllerProvider =
    AsyncNotifierProvider<RemindersController, bool>(RemindersController.new);
