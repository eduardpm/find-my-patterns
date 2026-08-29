import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';

/// Below this many days the streak line does not appear at all (#40): a
/// one-day streak is just today's entry, not a pattern worth naming, and
/// showing "1 day" the moment someone writes would read as a nag rather
/// than encouragement.
const int minVisibleWritingStreakDays = 2;

/// A quiet "N days writing" line for the Today header (#40).
///
/// No fire, no badge, no colour escalation as the number climbs -- the
/// number is the only thing that ever changes, and it changes in the same
/// muted, secondary text every other quiet fact on this screen is stated
/// in. There is no "streak lost" state: once the streak breaks the number
/// simply drops (or this widget stops being built at all, once it is below
/// [minVisibleWritingStreakDays]) rather than announcing the loss.
class WritingStreakLine extends StatelessWidget {
  /// Builds the streak line for [streakDays] consecutive days.
  ///
  /// Renders nothing at all below [minVisibleWritingStreakDays] -- safe to
  /// place unconditionally in a layout, the same way an empty [SizedBox]
  /// would be.
  const WritingStreakLine({super.key, required this.streakDays});

  /// The current writing streak, in days.
  final int streakDays;

  @override
  Widget build(BuildContext context) {
    if (streakDays < minVisibleWritingStreakDays) {
      return const SizedBox.shrink();
    }
    final journal = context.journalColors;
    final theme = Theme.of(context);
    return Semantics(
      label: 'Writing streak: $streakDays days',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note, size: 16, color: journal.onSurfaceVariant),
            const SizedBox(width: JournalSpacing.x1),
            Text(
              '$streakDays days writing',
              style: theme.textTheme.bodySmall?.copyWith(
                color: journal.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
