import 'package:flutter/material.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/pattern.dart';
import '../../core/theme/journal_metrics.dart';
import 'pattern_card.dart';

/// One collapsed row for a pattern `rankPatterns` (`pattern_ranking.dart`)
/// sorted into the weak tier (UX-2): a badge-less pattern, whose lift is
/// undefined or below the backend's minimum, or whose feeling carries no
/// valence to advise on either way (P0-2).
///
/// The caption is fixed copy, the same for every row, on purpose: which of
/// those three reasons applies is not a fact this client re-derives --
/// `pattern_ranking.dart`'s own doc comment says why -- so there is nothing
/// more specific it is entitled to say.
///
/// Collapsed by default; tapping swaps in the full [PatternCard] for
/// [pattern] in its place, so nothing about the pattern is ever hidden --
/// only deferred until asked for.
class WeakSignalRow extends StatefulWidget {
  /// Builds a collapsed row for [pattern].
  const WeakSignalRow({
    super.key,
    required this.pattern,
    required this.constants,
    required this.onOpenEntry,
  });

  /// The pattern this row stands for.
  final Pattern pattern;

  /// Forwarded to the full [PatternCard] once expanded.
  final EngineConstants constants;

  /// Forwarded to the full [PatternCard] once expanded.
  final void Function(String entryId, CalendarDate entryDate) onOpenEntry;

  @override
  State<WeakSignalRow> createState() => _WeakSignalRowState();
}

class _WeakSignalRowState extends State<WeakSignalRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (_expanded) {
      return PatternCard(
        pattern: widget.pattern,
        constants: widget.constants,
        onOpenEntry: widget.onOpenEntry,
      );
    }
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => setState(() => _expanded = true),
      borderRadius: JournalShapes.medium,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: JournalSpacing.x7),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: JournalSpacing.x3,
            vertical: JournalSpacing.x2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _captionFor(widget.pattern),
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: JournalSpacing.x2),
              Icon(
                Icons.expand_more,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "without screen time → content · not enough contrast yet" -- the topic,
/// prefixed with "without" for an inverse pattern (matching the full
/// card's own "Without it" badge), the feeling it did not clear the bar
/// with, and the one fixed reason every weak-tier row shares.
String _captionFor(Pattern pattern) {
  final subject = pattern.kind == PatternKind.inverse
      ? 'without ${pattern.topic}'
      : pattern.topic;
  final feeling = pattern.feeling?.label.toLowerCase() ?? 'a feeling';
  return '$subject → $feeling · not enough contrast yet';
}
