import 'package:flutter/material.dart';

import '../../core/diary/pattern.dart';
import '../../core/theme/journal_metrics.dart';
import 'insight_progress_copy.dart';

/// The insight progress surface (#37, L-2): a quiet counting section on the
/// "Entry saved" screen, under any [PatternEcho] panel, for the cold-start
/// gap before the diary has surfaced any pattern of its own.
///
/// Shown **after** an entry is saved, same as `PatternEchoPanel` — the
/// counts describe the entry that was just written, never bias the writing
/// itself. Every number comes from [progress] unchanged: this widget only
/// picks words and pluralisation around them (see `insight_progress_copy.dart`),
/// never a threshold, count, or rate of its own.
///
/// Deliberately quieter than [PatternEcho]'s own panel — smaller,
/// lower-contrast text and no card chrome — because this is an
/// in-progress count, not a finding: the visual weight itself is part of
/// "counts only, no prediction, no advice".
class InsightProgressPanel extends StatelessWidget {
  /// Builds the panel for [progress]. Renders nothing when
  /// [InsightProgress.hasContent] is false — a diary with no topic linked
  /// yet, or one already past the cold start, has nothing honest to add
  /// here.
  const InsightProgressPanel({super.key, required this.progress});

  final InsightProgress progress;

  @override
  Widget build(BuildContext context) {
    if (!progress.hasContent) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final closest = insightProgressClosestPairLine(progress);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: JournalSpacing.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(insightProgressTrackingLine(progress), style: bodyStyle),
          if (closest != null) ...[
            const SizedBox(height: JournalSpacing.x1),
            Text.rich(
              TextSpan(
                style: bodyStyle,
                children: [
                  TextSpan(text: closest.prefix),
                  TextSpan(
                    text: closest.pair,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: closest.suffix),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
