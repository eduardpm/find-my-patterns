import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/digest_settings_controller.dart';
import '../../core/settings/settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';
import 'reminders_card.dart';

const List<String> _weekdayLabels = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// The weekly digest toggle + day/time picker (R-2, task 2) — one pattern,
/// one recommendation, one movement figure, delivered as a local
/// notification. Off by default (issue #42), and unguarded: this is planned
/// as a paid-tier feature, but gating arrives with M-3, not here.
///
/// Wires into `ReminderService`/`DigestSlot` through
/// [DigestSettingsController], the exact shape [RemindersCard] already uses
/// for the reminders list — this card only ever renders
/// [AppSettings.digest] and hands a whole new [DigestTime] back to
/// [DigestSettingsController.save].
class DigestCard extends ConsumerWidget {
  /// Creates the Digest card.
  const DigestCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final schedule =
        ref.watch(settingsProvider).value?.digest ?? kDefaultDigestSchedule;
    final controller = ref.read(digestSettingsControllerProvider.notifier);
    final blocked = ref.watch(digestSettingsControllerProvider).value ?? false;

    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Weekly digest',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Semantics(
                label: 'Weekly digest',
                child: Switch(
                  value: schedule.enabled,
                  onChanged: (enabled) => unawaited(
                    controller.save(schedule.copyWith(enabled: enabled)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: JournalSpacing.x2),
          Text(
            'One pattern, one recommendation, one movement — once a week.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: JournalSpacing.x4),
          Row(
            children: [
              Expanded(
                child: _WeekdayDropdown(
                  weekday: schedule.weekday,
                  onChanged: (weekday) => unawaited(
                    controller.save(schedule.copyWith(weekday: weekday)),
                  ),
                ),
              ),
              const SizedBox(width: JournalSpacing.x3),
              TextButton(
                onPressed: () =>
                    unawaited(_pickTime(context, schedule, controller)),
                child: Text(_formatTime(schedule.hour, schedule.minute)),
              ),
            ],
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

  Future<void> _pickTime(
    BuildContext context,
    DigestTime schedule,
    DigestSettingsController controller,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: schedule.hour, minute: schedule.minute),
    );
    if (picked != null) {
      await controller.save(
        schedule.copyWith(hour: picked.hour, minute: picked.minute),
      );
    }
  }
}

/// The weekday chooser, a plain dropdown rather than a seven-way toggle row —
/// there is exactly one digest a week, so only one weekday is ever selected
/// at a time, unlike [RemindersCard]'s independent on/off switches.
class _WeekdayDropdown extends StatelessWidget {
  const _WeekdayDropdown({required this.weekday, required this.onChanged});

  /// [DateTime]'s convention: `1` (Monday) through `7` (Sunday).
  final int weekday;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      value: weekday,
      isExpanded: true,
      items: [
        for (var day = 1; day <= 7; day++)
          DropdownMenuItem(value: day, child: Text(_weekdayLabels[day - 1])),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

String _formatTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// The quiet inline note shown once the platform has refused notifications
/// while the digest is enabled — the exact copy and layout
/// [RemindersCard]'s own note uses, since it is the same fact about the same
/// plugin.
class _PermissionDeniedNote extends StatelessWidget {
  const _PermissionDeniedNote({required this.onOpenSettings});

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
                    'Notifications are off for this app, so the digest '
                    "won't show.",
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
