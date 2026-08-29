import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/journal_metrics.dart';
import '../../../core/widgets/journal.dart';
import 'export_controller.dart';
import 'export_format.dart';
import 'export_state.dart';

/// The Settings row that starts the whole-diary export (M-6): choose a
/// format, download it, hand it to the system share sheet.
///
/// Placed between Advanced and About on the Settings screen — the issue's
/// "above About" read exactly.
class ExportRow extends ConsumerWidget {
  /// Creates the export row.
  const ExportRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(exportControllerProvider);
    final inProgress = state is ExportInProgress;

    return JournalCard(
      onTap: inProgress ? null : () => unawaited(_chooseFormat(context, ref)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Export my diary',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (inProgress)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.share, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: JournalSpacing.x2),
          Text(
            'Choose Markdown or JSON, then share it with any app on your '
            'device. Free, always — nothing you export is paywalled.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (state is ExportError) ...[
            const SizedBox(height: JournalSpacing.x2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    state.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(exportControllerProvider.notifier).reset(),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _chooseFormat(BuildContext context, WidgetRef ref) async {
    final format = await showDialog<ExportFormat>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Export as'),
        children: [
          for (final format in ExportFormat.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(format),
              child: Text(format.label),
            ),
        ],
      ),
    );
    if (format == null) return;
    await ref.read(exportControllerProvider.notifier).export(format);
  }
}
