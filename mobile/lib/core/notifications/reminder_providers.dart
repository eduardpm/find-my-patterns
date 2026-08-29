import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications_plugin.dart';
import 'reminder_service.dart';

/// The service the app schedules and listens to the four daily check-in
/// reminders through.
///
/// Overridable so tests can inject a [ReminderService] wired to a fake
/// [NotificationsPlugin] instead of a real platform channel.
final reminderServiceProvider = Provider<ReminderService>(
  (ref) => ReminderService(plugin: const DefaultNotificationsPlugin()),
);

/// A monotonic count of reminder taps the app shell should react to by
/// opening the entry composer.
///
/// A counter, not a `bool` — ported from `MainActivity.openComposerSignal`
/// (Kotlin), which increments rather than sets a flag specifically so a
/// second tap re-fires the navigation request even while the composer the
/// first tap opened is still on screen. A `bool` cannot express "already
/// true, but act again anyway."
///
/// [build] subscribes to [ReminderService.taps] directly with
/// [Stream.listen] rather than through a `StreamProvider` watched with
/// `ref.listen`: a `StreamProvider` exposes an `AsyncValue`, and Riverpod
/// skips notifying a listener when the new value compares equal to the
/// last one. [ReminderTap] has value equality, so the same slot tapped
/// twice in a row — exactly the case this counter exists to handle —
/// would silently coalesce into a single increment through that path. A
/// raw stream subscription has no such deduplication: every event
/// increments, regardless of what the last one carried.
class OpenComposerSignal extends Notifier<int> {
  @override
  int build() {
    final subscription = ref.watch(reminderServiceProvider).taps.listen((_) {
      state++;
    });
    ref.onDispose(subscription.cancel);
    return 0;
  }

  /// Checks whether a reminder tap cold-started the app and, if so, signals
  /// the app shell to open the composer for it.
  ///
  /// Call this once, from the app shell, right after
  /// [ReminderService.initialize] — a cold start is only readable once, at
  /// startup; every tap that happens after that arrives through [build]'s
  /// subscription instead.
  Future<void> checkLaunchTap() async {
    final tap = await ref.read(reminderServiceProvider).launchTap();
    if (tap != null) state++;
  }
}

/// The signal the app shell watches to know when to navigate to the entry
/// composer.
final openComposerSignalProvider = NotifierProvider<OpenComposerSignal, int>(
  OpenComposerSignal.new,
);
