import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/diary/entry.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/theme/journal_typography.dart';
import '../../core/widgets/feeling_accent.dart';
import '../../core/widgets/feeling_chips.dart';
import '../../core/widgets/journal.dart';

/// One entry in the day's list.
///
/// The colour rail down the leading edge is the entry's primary feeling —
/// a second, redundant encoding, since the feeling is also spelled out in
/// the card's header, but it is what lets a week of entries be skimmed for
/// shape rather than read. Every feeling is shown, not just the primary
/// one, wrapping rather than clipping: the last of four feelings is not
/// decoration.
class EntryCard extends StatelessWidget {
  /// Builds a card for [entry].
  const EntryCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.maxLines = 5,
  });

  /// The entry to show.
  final Entry entry;

  /// Called when the card is tapped.
  final VoidCallback onTap;

  /// How many lines of [Entry.rawText] to show before ellipsising the rest.
  ///
  /// Defaults to the Today feed's own five lines; the day-entries screen
  /// passes six, so this stays additive rather than changing what Today
  /// already shows.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    final theme = Theme.of(context);
    final railColor = entry.feeling?.accent(journal) ?? journal.hairline;
    const shape = JournalShapes.large;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        border: Border.all(color: journal.hairline),
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: Material(
          color: theme.colorScheme.surfaceContainer,
          child: InkWell(
            onTap: onTap,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: railColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(JournalSpacing.x4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // One shared `Wrap`, not a `Row` with the time
                          // pinned in a fixed-width slot ahead of an
                          // `Expanded(Wrap(...))` (#168). That shape starves
                          // the `Expanded` at large text scales, and a
                          // `Wrap` cannot break a single child in two, so
                          // each `FeelingChip` was squeezed until its own
                          // one-word label broke mid-word instead -- at
                          // 320dp/2x "Relaxed" wanted 196px and was given
                          // 43.5px. Nothing overflowed and nothing threw,
                          // which is why it survived a sweep.
                          //
                          // `day_entries_screen.dart`'s `_DayEntryCard` was
                          // moved off the identical shape by #155; this is
                          // the same fix, and `WrapAlignment.end` goes with
                          // it -- with the time inside the same `Wrap`,
                          // end-alignment would push the whole row right and
                          // leave the gutter it was creating before.
                          Wrap(
                            spacing: JournalSpacing.x2,
                            runSpacing: JournalSpacing.x1,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Eyebrow(
                                DateFormat.jm().format(
                                  entry.createdAt.toLocal(),
                                ),
                              ),
                              for (final feeling in entry.feelings)
                                FeelingChip(
                                  label: feeling.label,
                                  color: feeling.accent(journal),
                                ),
                            ],
                          ),
                          const SizedBox(height: JournalSpacing.x2),
                          Text(
                            entry.rawText,
                            style: JournalType.prose.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: maxLines,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
