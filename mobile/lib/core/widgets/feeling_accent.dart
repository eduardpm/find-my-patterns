import 'package:flutter/material.dart';

import '../diary/feeling.dart';
import '../theme/journal_palette.dart';

/*
 * `core/theme` deliberately never imports `core/diary` (see
 * `journal_palette.dart`), so its colour lookups are keyed on the plain wire
 * strings the backend sends rather than on [Feeling] or [FeelingGroup].
 * These extensions are the one place that bridges the two: every widget that
 * needs "this feeling's colour" or "this group's colour" reaches for
 * [FeelingAccent.accent] / [FeelingGroupAccent.accent] instead of
 * reimplementing the `groupKey`/`valenceId` plumbing itself.
 */

/// A feeling's accent colour, resolved through [JournalColors.feelings].
extension FeelingAccent on Feeling {
  /// This feeling's accent in [journal] — its own group's colour, or the
  /// fallback for its [Feeling.valence] when [Feeling.groupKey] names a
  /// group this build has never seen.
  Color accent(JournalColors journal) => journal.feelings.forFeeling(
    groupKey: groupKey,
    valenceId: valence.name,
  );
}

/// A feeling group's accent colour, resolved the same way as
/// [FeelingAccent.accent].
///
/// Every feeling inside a group carries that group's own valence, so a
/// group's accent is its own key resolved through the identical lookup —
/// there is nothing group-specific about the colour beyond that.
extension FeelingGroupAccent on FeelingGroup {
  /// This group's accent in [journal].
  Color accent(JournalColors journal) =>
      journal.feelings.forFeeling(groupKey: key, valenceId: valence.name);
}
