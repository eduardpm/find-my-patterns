import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/journal_metrics.dart';

/// The one surface every premium-only feature renders through (M-3, #48).
///
/// The issue's copy rule is the whole point of this widget existing as a
/// single, reused thing rather than being re-typed at each call site:
/// locked states **state facts about scope**, never FOMO --
/// "Last 30 days shown." and "Patterns across your full 14 months —
/// Premium." are the issue's own two examples, and both are just [message]
/// here. [onUpgrade] is what tells the two apart: `null` renders a quiet,
/// buttonless note about what is already on screen (the first example);
/// non-null adds the Upgrade action for a feature genuinely out of reach
/// (the second). Neither ever blurs, dims, or fabricates the data
/// underneath -- every call site replaces the locked content outright
/// rather than layering this over it, per the product constitution's
/// "never fake blurred data".
///
/// Never used for anything the constitution forbids gating -- writing,
/// reading back, or export. `test/features/premium/free_features_ungated_test.dart`
/// asserts that directly: those screens never import this widget.
class PremiumLock extends StatelessWidget {
  /// Builds a lock stating [message], with an Upgrade action when
  /// [onUpgrade] is given.
  const PremiumLock({super.key, required this.message, this.onUpgrade});

  /// The fact this locked state states, phrased from real numbers the
  /// backend sent -- never a guess, never urgency.
  final String message;

  /// Opens the placeholder upgrade screen, or `null` for a note with
  /// nothing to unlock.
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journal = context.journalColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: journal.surfaceVariant,
        borderRadius: JournalShapes.medium,
      ),
      child: Padding(
        padding: const EdgeInsets.all(JournalSpacing.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 20,
              color: journal.onSurfaceVariant,
            ),
            const SizedBox(width: JournalSpacing.x3),
            // `message` and the `Upgrade` button share this `Expanded`
            // through a `Wrap` rather than sitting as two more `Row`
            // siblings (#173): the old `Row` counted the button at its full
            // natural width before dividing what was left between the icon,
            // the spacers and the message's own `Expanded`, so once the
            // button's grown label plus the fixed icon and spacers already
            // outgrew the row -- 8px over, at 320dp/2x, with `onUpgrade`
            // set -- there was nothing left to give and the row overflowed
            // outright. Squeezing the button into a share of the remaining
            // space instead (`Flexible` sized by a flex ratio, the fix this
            // shape usually takes) was rejected here: "Upgrade" is one word,
            // and a flex split narrow enough to close an 8px gap would
            // routinely be narrower than the word's own single-line width,
            // breaking it mid-word instead. `Wrap` keeps the button (and
            // the message) at their full natural size always, and drops the
            // button to its own line only on the rare cell where the two
            // cannot share one.
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: JournalSpacing.x3,
                runSpacing: JournalSpacing.x2,
                children: [
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: journal.onSurfaceVariant,
                    ),
                  ),
                  if (onUpgrade != null)
                    OutlinedButton(
                      onPressed: onUpgrade,
                      child: const Text('Upgrade'),
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
