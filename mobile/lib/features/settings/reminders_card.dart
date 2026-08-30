import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/reminder_settings_controller.dart';
import '../../core/settings/settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';

/// A neutral, uncommitted time for a freshly added reminder.
///
/// The user picks a real time next — this only has to be a valid clock
/// value, not a guess at what they want. Fixed rather than derived from
/// [DateTime.now], so adding a reminder is deterministic and testable.
const int _newReminderHour = 12;
const int _newReminderMinute = 0;

/// Up to six reminders the user can turn on, re-time, or remove — the
/// settings-side half of R-UX-10b. Wires into the existing
/// `ReminderService`/`ReminderSlot` scheduling through
/// [RemindersController]; this card only ever renders [AppSettings.reminders]
/// and hands a whole new list back to [RemindersController.save].
///
/// Ported in spirit from the Kotlin app's four fixed daily alarms, but every
/// slot here is something the user chose, starting from [kDefaultReminders]
/// on a fresh install — two suggestions, both off.
class RemindersCard extends ConsumerWidget {
  /// Creates the Reminders card.
  const RemindersCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reminders =
        ref.watch(settingsProvider).value?.reminders ?? kDefaultReminders;
    final controller = ref.read(remindersControllerProvider.notifier);
    final blocked = ref.watch(remindersControllerProvider).value ?? false;

    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reminders', style: theme.textTheme.titleMedium),
          const SizedBox(height: JournalSpacing.x2),
          Text(
            'A quiet nudge to write, at the times you choose. Off until you '
            'turn one on.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: JournalSpacing.x5),
          for (var i = 0; i < reminders.length; i++) ...[
            if (i > 0) const SizedBox(height: JournalSpacing.x2),
            _ReminderRow(
              reminder: reminders[i],
              onToggle: (enabled) => unawaited(
                controller.save(_replaceAt(reminders, i, enabled: enabled)),
              ),
              onTimeChanged: (hour, minute) => unawaited(
                controller.save(
                  _replaceAt(reminders, i, hour: hour, minute: minute),
                ),
              ),
              onRemove: () => unawaited(
                controller.save([...reminders]..removeAt(i)),
              ),
            ),
          ],
          const SizedBox(height: JournalSpacing.x3),
          if (reminders.length < ReminderTime.maxCount)
            OutlinedButton.icon(
              onPressed: () => unawaited(
                controller.save([
                  ...reminders,
                  const ReminderTime(
                    hour: _newReminderHour,
                    minute: _newReminderMinute,
                  ),
                ]),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add reminder'),
            ),
          if (blocked) ...[
            const SizedBox(height: JournalSpacing.x4),
            _PermissionDeniedNote(
              onOpenSettings: controller.openSystemSettings,
            ),
          ],
        ],
      ),
    );
  }

  static List<ReminderTime> _replaceAt(
    List<ReminderTime> reminders,
    int index, {
    int? hour,
    int? minute,
    bool? enabled,
  }) => [
    for (var i = 0; i < reminders.length; i++)
      if (i == index)
        reminders[i].copyWith(hour: hour, minute: minute, enabled: enabled)
      else
        reminders[i],
  ];
}

/// One reminder's row: its time, an on/off switch, and a way to remove it.
class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.onToggle,
    required this.onTimeChanged,
    required this.onRemove,
  });

  final ReminderTime reminder;
  final ValueChanged<bool> onToggle;
  final void Function(int hour, int minute) onTimeChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _formatTime(reminder.hour, reminder.minute);
    return ConstrainedBox(
      // 48dp: the touch-target floor, since the row is otherwise only as
      // tall as its text and the switch.
      constraints: const BoxConstraints(minHeight: JournalSpacing.x7),
      // `Wrap`, not `Row`: at 320dp/2x the sweep measured this row's time
      // label needing 170px while an `Expanded` sharing the row with the
      // switch and remove button only had 164px left to give it -- both
      // controls already sit at their own required minimum (the switch's
      // intrinsic size, the remove button's 48dp touch-target floor), so
      // there is no room to reclaim from them. Grouping the switch and
      // remove button as one `Wrap` child, instead of splitting the time
      // label across an `Expanded`, means the time -- the load-bearing
      // value here -- is always laid out at its own full natural width;
      // the switch/remove group simply drops to its own line on the rare
      // screen too narrow to hold both, rather than the time ever being
      // squeezed smaller than it needs.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: JournalSpacing.x1,
        children: [
          TextButton(
            onPressed: () => unawaited(_pickTime(context)),
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.zero,
            ),
            child: Text(label, style: theme.textTheme.titleMedium),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: '$label reminder',
                child: Switch(value: reminder.enabled, onChanged: onToggle),
              ),
              // `tooltip` alone would only reach the semantics tree's
              // `tooltip` field, not its `label` -- the accessible name a
              // screen reader announces -- so this replaces `IconButton`'s
              // own semantics with an explicit one (the same pattern
              // `pattern_echo_panel.dart`'s dismiss button uses).
              Semantics(
                container: true,
                button: true,
                label: 'Remove $label reminder',
                onTap: onRemove,
                child: ExcludeSemantics(
                  child: IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove $label reminder',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: reminder.hour, minute: reminder.minute),
    );
    if (picked != null) onTimeChanged(picked.hour, picked.minute);
  }
}

String _formatTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// The quiet inline note shown once the platform has refused notifications
/// for at least one enabled reminder.
///
/// Deliberately understated -- a line of body text and a text link, not a
/// banner or a dialog -- since a user who already said no to the system
/// prompt should not be confronted about it every time they open Settings.
class _PermissionDeniedNote extends StatelessWidget {
  const _PermissionDeniedNote({required this.onOpenSettings});

  /// Opens the OS notification-settings screen.
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: JournalShapes.medium,
      ),
      child: Padding(
        padding: const EdgeInsets.all(JournalSpacing.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: JournalSpacing.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Notifications are off for this app, so reminders won't "
                    'show.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    onPressed: () => unawaited(onOpenSettings()),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('Grant in system settings'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
