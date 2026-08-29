import 'package:flutter/material.dart';

import '../diary/pattern.dart';
import '../theme/journal_metrics.dart';
import '../theme/journal_typography.dart';
import 'journal.dart';

/// What the diary already says about the topics in an entry that has just
/// been saved.
///
/// Shown **after** an entry is saved and never during composition: an app
/// that said "you usually feel anxious about meetings" while someone was
/// still describing the meeting would be shaping the evidence it then
/// counts. Callers must not reuse this panel on the composer.
///
/// It states an observation and stops — [PatternEcho.narrativeText] is
/// shown exactly as the pattern card wrote it, with no prediction, no
/// advice, and nothing about how the user feels today. Dismissing the panel
/// (see [onDismiss]) affects nothing but this panel; it does not touch the
/// pattern the echo describes.
class PatternEchoPanel extends StatelessWidget {
  /// Builds a panel for [echoes]. Renders nothing when [echoes] is empty.
  const PatternEchoPanel({
    super.key,
    required this.echoes,
    required this.onDismiss,
  });

  /// The patterns this entry touched, each with its own narrative sentence.
  final List<PatternEcho> echoes;

  /// Called when the dismiss button is tapped. Dismissing is this panel's
  /// own business — it never mutates or hides the underlying pattern.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (echoes.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: JournalSpacing.x2),
                  Flexible(
                    child: Text(
                      'You have written about this before',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              // `tooltip` alone would only reach the semantics tree's
              // `tooltip` field, not its `label` — the accessible name a
              // screen reader announces — so this replaces `IconButton`'s
              // own semantics with an explicit one, the same pattern
              // `Eyebrow` uses for a similar mismatch.
              Semantics(
                container: true,
                button: true,
                label: 'Dismiss',
                onTap: onDismiss,
                child: ExcludeSemantics(
                  child: IconButton(
                    onPressed: onDismiss,
                    tooltip: 'Dismiss',
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ],
          ),
          for (final echo in echoes) ...[
            const SizedBox(height: JournalSpacing.x3),
            Text(
              echo.narrativeText,
              style: JournalType.prose.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
