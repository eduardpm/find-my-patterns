import 'package:flutter/material.dart';

import '../diary/feeling.dart';
import '../theme/app_theme.dart';
import '../theme/journal_metrics.dart';
import '../theme/journal_palette.dart';
import 'feeling_accent.dart';
import 'journal.dart';

/// The optional per-feeling intensity rows, one row of stops per feeling on
/// the entry.
///
/// Four things about it are requirements, not taste — carried over from the
/// Kotlin original rather than reinvented:
///
///  * **Optional, every row defaulting to off.** The two-tap capture flow is
///    why anyone keeps this diary; a required rating would slow every entry
///    down to serve a feature most entries will not use. [Eyebrow] says
///    "Optional" in words rather than leaving it implied by the rows being
///    empty.
///  * **One row of stops per feeling, not a slider.** A handful of stops is
///    what the signal needs and what a person can answer without
///    deliberating — a 1–100 scale would buy precision the answer does not
///    have.
///  * **The stops come from the backend.** [min] and [max] arrive with the
///    insights payload (`EngineConstants.minIntensity`/`maxIntensity`); this
///    widget renders the scale rather than defining it.
///  * **Every chosen feeling gets its own row.** Rating only "the primary
///    feeling" would mean an entry that was *grateful and anxious* could say
///    how strongly it was grateful and nothing at all about the anxious
///    half. Ratings travel keyed by [Feeling.key], so removing a word takes
///    its rating with it.
class IntensityDials extends StatelessWidget {
  /// Builds the intensity rows for [feelings]. Renders nothing when
  /// [feelings] is empty.
  const IntensityDials({
    super.key,
    required this.feelings,
    required this.intensities,
    required this.onChange,
    required this.min,
    required this.max,
  });

  /// The feelings to rate, each getting its own row in this order.
  final List<Feeling> feelings;

  /// The stored value for each feeling, keyed by [Feeling.key]. A feeling
  /// missing from this map has no value yet.
  final Map<String, int> intensities;

  /// Called with the new value for the given [Feeling], or `null` to clear
  /// it.
  final void Function(Feeling feeling, int? value) onChange;

  /// The lowest stop on the scale, served by the backend.
  final int min;

  /// The highest stop on the scale, served by the backend.
  final int max;

  @override
  Widget build(BuildContext context) {
    if (feelings.isEmpty) return const SizedBox.shrink();
    final journal = context.journalColors;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: JournalShapes.medium,
        border: Border.all(color: journal.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(JournalSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    feelings.length == 1
                        ? 'How strongly?'
                        : 'How strongly did you feel each?',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: JournalSpacing.x2),
                const Eyebrow('Optional'),
              ],
            ),
            for (var i = 0; i < feelings.length; i++) ...[
              if (i > 0) ...[
                const SizedBox(height: JournalSpacing.x3),
                Divider(color: journal.hairline, height: 1),
              ],
              const SizedBox(height: JournalSpacing.x3),
              _IntensityRow(
                feeling: feelings[i],
                value: intensities[feelings[i].key],
                onChange: (value) => onChange(feelings[i], value),
                min: min,
                max: max,
                journal: journal,
              ),
            ],
            const SizedBox(height: JournalSpacing.x3),
            Text(
              'Skip any of these and nothing changes — patterns never '
              'depend on them.',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// One feeling's label and its row of stops.
class _IntensityRow extends StatelessWidget {
  const _IntensityRow({
    required this.feeling,
    required this.value,
    required this.onChange,
    required this.min,
    required this.max,
    required this.journal,
  });

  final Feeling feeling;
  final int? value;
  final ValueChanged<int?> onChange;
  final int min;
  final int max;
  final JournalColors journal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = feeling.accent(journal);
    final currentValue = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FeelingDot(color: accent),
            const SizedBox(width: JournalSpacing.x2),
            Expanded(
              child: Text(
                feeling.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (currentValue != null)
              TextButton(
                onPressed: () => onChange(null),
                child: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: JournalSpacing.x2),
        Row(
          children: [
            for (var stop = min; stop <= max; stop++) ...[
              if (stop > min) const SizedBox(width: JournalSpacing.x2),
              _IntensityStop(
                feeling: feeling,
                stop: stop,
                max: max,
                filled: currentValue != null && stop <= currentValue,
                // Tapping the current value clears it: the way out of an
                // optional field has to be as cheap as the way in, or
                // "optional" only holds until the first tap.
                onTap: () => onChange(currentValue == stop ? null : stop),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// One circular stop inside a feeling's row.
class _IntensityStop extends StatelessWidget {
  const _IntensityStop({
    required this.feeling,
    required this.stop,
    required this.max,
    required this.filled,
    required this.onTap,
  });

  final Feeling feeling;
  final int stop;
  final int max;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final journal = context.journalColors;
    return Semantics(
      // Its own boundary so it reads as one stop rather than merging into
      // the row (or the whole panel) it sits inside.
      container: true,
      button: true,
      // Named per feeling, because there is more than one row of stops on
      // screen and "3 of 5" alone would not say which word it rates.
      label: '${feeling.label}, $stop of $max',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              // 48dp: the constitution's touch-target floor. The ported
              // Kotlin used 44dp; this widens it to meet that floor.
              width: JournalSpacing.x7,
              height: JournalSpacing.x7,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled
                    ? colors.primaryContainer
                    : colors.surfaceContainer,
                border: Border.all(
                  color: filled ? colors.primary : journal.hairline,
                ),
              ),
              child: Text(
                '$stop',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: filled ? FontWeight.bold : FontWeight.normal,
                  color: filled ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
