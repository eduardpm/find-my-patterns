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
    final subscription = ref.watch(reminderServiceProvider).taps.listen((tap) {
      // Only a reminder opens the composer -- a first-pattern tap
      // (#38) goes to Insights instead, through
      // [OpenInsightsSignal], which shares this same tap stream.
      if (tap is ReminderTap) state++;
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
    if (tap is ReminderTap) state++;
  }
}

/// The signal the app shell watches to know when to navigate to the entry
/// composer.
final openComposerSignalProvider = NotifierProvider<OpenComposerSignal, int>(
  OpenComposerSignal.new,
);

/// A monotonic count of events the app shell should react to by navigating
/// to Insights: a tap on the first-pattern celebration notification (#38),
/// cold or warm, or the inline celebration card's own "see the evidence"
/// tap bumping this directly (see `EntryComposerScreen`).
///
/// A counter rather than a `bool`, for the same reason
/// [OpenComposerSignal] is: a second navigation request must still move
/// even if the first already landed on Insights and nothing about the
/// destination looks different.
class OpenInsightsSignal extends Notifier<int> {
  @override
  int build() {
    final subscription = ref.watch(reminderServiceProvider).taps.listen((tap) {
      if (tap is FirstPatternTap) state++;
    });
    ref.onDispose(subscription.cancel);
    return 0;
  }

  /// Checks whether the first-pattern notification cold-started the app
  /// and, if so, signals the app shell to open Insights for it. Call this
  /// once, from the app shell, right after [ReminderService.initialize] —
  /// see [OpenComposerSignal.checkLaunchTap] for why a cold start needs its
  /// own explicit read.
  Future<void> checkLaunchTap() async {
    final tap = await ref.read(reminderServiceProvider).launchTap();
    if (tap is FirstPatternTap) state++;
  }

  /// Signals the app shell to open Insights right now.
  ///
  /// The inline first-pattern celebration card's own "see the evidence"
  /// tap calls this directly (see `EntryComposerScreen`) rather than
  /// waiting on a notification tap that, on that path, never happens --
  /// the card is only shown when the app is already in the foreground, so
  /// there is no OS notification behind it to tap.
  void bump() => state++;
}

/// The signal the app shell watches to know when to navigate to Insights.
final openInsightsSignalProvider = NotifierProvider<OpenInsightsSignal, int>(
  OpenInsightsSignal.new,
);

/// A monotonic count of taps on the weekly digest notification (R-2), cold
/// or warm -- the same counter shape [OpenComposerSignal] and
/// [OpenInsightsSignal] use, and for the same reason: a second tap must
/// still act even if the digest sheet the first tap opened is still on
/// screen.
class OpenDigestSignal extends Notifier<int> {
  @override
  int build() {
    final subscription = ref.watch(reminderServiceProvider).taps.listen((tap) {
      if (tap is DigestTap) state++;
    });
    ref.onDispose(subscription.cancel);
    return 0;
  }

  /// Checks whether the digest notification cold-started the app and, if so,
  /// signals the app shell to open the digest sheet for it. Call this once,
  /// from the app shell, right after [ReminderService.initialize] -- see
  /// [OpenComposerSignal.checkLaunchTap] for why a cold start needs its own
  /// explicit read.
  Future<void> checkLaunchTap() async {
    final tap = await ref.read(reminderServiceProvider).launchTap();
    if (tap is DigestTap) state++;
  }
}

/// The signal the app shell watches to know when to open the digest sheet.
final openDigestSignalProvider = NotifierProvider<OpenDigestSignal, int>(
  OpenDigestSignal.new,
);
