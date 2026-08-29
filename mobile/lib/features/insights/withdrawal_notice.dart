import 'package:flutter/material.dart';

import '../../core/diary/pattern.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';

/// A pattern that stopped qualifying, and why.
///
/// The point of this widget is that a withdrawal is an *event*, not an
/// absence. Before it existed, a pattern the user had read and acted on
/// could disappear between two visits with nothing said, which is
/// indistinguishable from the app having been wrong the first time. Here it
/// is a notice, with the previous count, the new one, and a reason drawn
/// from a fixed set the backend decides -- never a sentence a model wrote.
///
/// Every word and number below arrives in the payload. This widget chooses
/// the icon and the layout.
class WithdrawalNotice extends StatelessWidget {
  /// Builds a notice for [withdrawal].
  const WithdrawalNotice({super.key, required this.withdrawal});

  /// The withdrawal to show.
  final Withdrawal withdrawal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Unacknowledged notices are marked, so "since you last looked" is
    // visible and not just counted.
    final accent = withdrawal.isNew
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    final container = withdrawal.isNew
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final topic = withdrawal.topic;
    final capitalisedTopic = topic.isEmpty
        ? topic
        : topic[0].toUpperCase() + topic.substring(1);
    // An inverse pattern was a claim about the entries that did *not*
    // mention the topic, and the heading has to say so or it reads as the
    // forward pattern going away instead.
    final heading = withdrawal.kind == PatternKind.inverse
        ? 'Without ${withdrawal.topic} → ${withdrawal.feeling}'
        : '$capitalisedTopic → ${withdrawal.feeling}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: container,
        borderRadius: JournalShapes.medium,
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(JournalSpacing.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.history,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: JournalSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading, style: theme.textTheme.titleSmall),
                  const SizedBox(height: JournalSpacing.x1),
                  // On its own line rather than beside the title. Sharing a
                  // row let the badge be squeezed to whatever the topic
                  // name left over, and a long reason then wrapped
                  // mid-word into an unreadable blob on a long topic.
                  StatusBadge(
                    _reasonLabel(withdrawal.reason),
                    contentColor: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: JournalSpacing.x1),
                  Text(
                    withdrawal.detailText,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: JournalSpacing.x1),
                  Eyebrow(_countLine(withdrawal)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Presentation only. The reason itself is the backend's, and there are
/// five of them.
///
/// Each label names the thing that actually changed, which is only
/// possible because the codes distinguish them: "Not enough left" beside a
/// count of 12 → 12 would be false, and that is exactly what a single
/// "below threshold" covering both cases would force this badge to say.
/// [WithdrawalReason.excludedUnpaired] gets its own label for the same
/// reason -- "No confirmed feelings" is false of these entries, which is
/// the whole bug #109 fixes.
String _reasonLabel(WithdrawalReason reason) => switch (reason) {
  WithdrawalReason.belowThreshold => 'Not enough left',
  WithdrawalReason.belowLift => 'Association too weak',
  WithdrawalReason.noLongerConfirmed => 'No confirmed feelings',
  WithdrawalReason.topicMerged => 'Topic merged',
  WithdrawalReason.excludedUnpaired => 'Needs pairing',
};

/// The evidence line under the reason badge.
///
/// `previousCount → newCount` is only evidence of a change when the two
/// numbers actually differ -- "2 → 2" beside "was withdrawn" is the exact
/// self-contradiction #109 was filed over (a mixed-valence pair's
/// unexcluded mention count is the same before and after #26's rule, only
/// the *count that counts* moved). A pattern's own [Withdrawal.reason] is
/// what changed in that case, not either number, so the line falls back to
/// stating the single count rather than a delta that reads as none.
String _countLine(Withdrawal withdrawal) =>
    withdrawal.previousCount == withdrawal.newCount
    ? '${withdrawal.newCount} occurrences'
    : '${withdrawal.previousCount} → ${withdrawal.newCount}';
