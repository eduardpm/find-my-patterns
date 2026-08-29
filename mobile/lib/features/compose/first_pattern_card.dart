import 'package:flutter/material.dart';

import '../../core/diary/pattern.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/theme/journal_typography.dart';
import '../../core/widgets/journal.dart';
import 'first_pattern_copy.dart';

/// The first-pattern celebration (L-3/#38), shown inline on the composer's
/// "Saved" screen the moment `EntryComposerController` detects the diary's
/// very first pattern crossing threshold, while the app is in the
/// foreground on that screen.
///
/// A card on the same "Saved" screen `PatternEchoPanel` already occupies,
/// not a snackbar or a dialog: this is the one moment the ticket calls the
/// product's aha moment, and the quiet, single-purpose screen an entry
/// already lands on after saving is exactly where it belongs, rather than
/// competing for attention with something more disruptive.
///
/// Deliberately modest -- no confetti, no colour change, no animation. The
/// evidence rule this app holds every pattern card to applies here too:
/// this widget itself names no number (see [firstPatternCardText]), and
/// what it claims is only what [pattern] already backs.
class FirstPatternCard extends StatelessWidget {
  /// Builds the card for [pattern] -- the diary's first pattern.
  ///
  /// [onTap] is called when the card is tapped; the caller decides what
  /// "see the evidence" means. `EntryComposerScreen` closes the composer
  /// and signals the app shell to open Insights.
  const FirstPatternCard({
    super.key,
    required this.pattern,
    required this.onTap,
  });

  /// The pattern being celebrated.
  ///
  /// Held rather than just its evidence count so a future revision of this
  /// card can show more about it without `EntryComposerController` having
  /// to change what it hands over -- today, only [firstPatternCardText]'s
  /// fixed copy is shown, no field of [pattern] read directly here.
  final Pattern pattern;

  /// Called when the card is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JournalCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Nudges the icon down to sit with the text's cap height,
            // mirroring `PatternEchoPanel`'s own icon alignment.
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.insights_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: JournalSpacing.x2),
          Expanded(
            child: Text(
              firstPatternCardText,
              style: JournalType.prose.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
