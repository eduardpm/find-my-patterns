import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/pattern.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/theme/journal_typography.dart';
import '../../core/widgets/feeling_accent.dart';
import '../../core/widgets/feeling_chips.dart';
import '../../core/widgets/journal.dart';

/// One detected pattern, and the entries behind it.
///
/// Every value here is displayed as received. Nothing on this card is
/// derived, re-counted, re-rated or reworded -- not the direction, not the
/// rates, not the lift, not the narrative, and not the evidence trail,
/// which renders in the order the backend sent it. The web client shows the
/// same numbers from the same payload, which is the only way the two
/// clients can be guaranteed to agree about the same diary.
///
/// What this widget owns is presentation: which badge, which colour, what
/// opens on a tap, and the topic's leading capital.
class PatternCard extends StatefulWidget {
  /// Builds a card for [pattern].
  const PatternCard({
    super.key,
    required this.pattern,
    required this.constants,
    required this.onOpenEntry,
  });

  /// The pattern to show.
  final Pattern pattern;

  /// The thresholds the engine applied, read from the same response --
  /// never hardcoded here, so a screen showing "in 30 days" keeps reading
  /// the 30 from the backend even after that number changes on one side.
  final EngineConstants constants;

  /// Called with an evidence row's entry id and its date when "Open" is
  /// tapped.
  ///
  /// Both, because the detail route is keyed on both, and the trail already
  /// carries both -- loading the entry first just to build a URL would be a
  /// round trip to learn something already known.
  final void Function(String entryId, CalendarDate entryDate) onOpenEntry;

  @override
  State<PatternCard> createState() => _PatternCardState();
}

/// Which badge, if any, a pattern card shows for [pattern] (P0-2).
///
/// [Pattern.direction] already resolves keep/change/no-opinion on the
/// backend, from the pattern's kind, its feeling's valence, and -- since
/// P0-6 -- its lift: `badgeDirectionFor` in
/// `backend/src/insights/patterns.service.ts` withholds the badge for a
/// pattern whose lift is undefined or below the minimum, the same early
/// return this file once expected to make locally. This function only
/// translates the already-resolved value into what the badge shows and
/// never re-derives keep or change -- or now, re-checks the lift -- itself;
/// doing either here would be this client disagreeing with the backend
/// about the same diary (see the module doc comment above).
PatternDirection? patternBadgeFor(Pattern pattern) =>
    switch (pattern.direction) {
      PatternDirection.none => null,
      final badge => badge,
    };

class _PatternCardState extends State<PatternCard> {
  bool _showEvidence = false;

  @override
  void didUpdateWidget(covariant PatternCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different pattern occupying the same slot (a refreshed list) starts
    // collapsed again rather than keeping whatever the previous card's
    // toggle happened to be set to.
    if (oldWidget.pattern.id != widget.pattern.id) {
      _showEvidence = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pattern = widget.pattern;
    final journal = context.journalColors;
    final theme = Theme.of(context);
    final badge = patternBadgeFor(pattern);
    final isChange = badge == PatternDirection.change;
    final isHistorical = pattern.status == PatternStatus.historical;
    final isInverse = pattern.kind == PatternKind.inverse;
    final badgeColor = isChange
        ? theme.colorScheme.onErrorContainer
        : journal.success;
    final badgeContainer = isChange
        ? theme.colorScheme.errorContainer
        : journal.successContainer;
    final topic = pattern.topic;
    final capitalisedTopic = topic.isEmpty
        ? topic
        : topic[0].toUpperCase() + topic.substring(1);

    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(capitalisedTopic, style: theme.textTheme.titleLarge),
                    if (isInverse || isHistorical || pattern.isStrong) ...[
                      const SizedBox(height: JournalSpacing.x2),
                      Wrap(
                        spacing: JournalSpacing.x2,
                        runSpacing: JournalSpacing.x2,
                        children: [
                          // The inverse card is a different claim about the
                          // same table -- the feeling went with the topic's
                          // *absence* -- so it says so in words rather than
                          // relying on a tint.
                          if (isInverse)
                            StatusBadge(
                              'Without it',
                              contentColor: journal.accent,
                              containerColor: journal.accentContainer,
                            ),
                          if (isHistorical)
                            StatusBadge(
                              'Historical',
                              contentColor: theme.colorScheme.onSurfaceVariant,
                              containerColor:
                                  theme.colorScheme.surfaceContainerHighest,
                            ),
                          if (pattern.isStrong)
                            StatusBadge(
                              'Strong',
                              contentColor: theme.colorScheme.primary,
                              containerColor:
                                  theme.colorScheme.primaryContainer,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // A neutral-valence pattern (P0-2) carries no badge at all --
              // neither colour has anything to say about it -- so nothing
              // renders here rather than defaulting to either one.
              if (badge != null) ...[
                const SizedBox(width: JournalSpacing.x3),
                // Direction is carried by an arrow icon and a word, never by
                // colour alone, so the card survives greyscale.
                StatusBadge(
                  isChange ? 'Consider changing' : 'Keep doing',
                  contentColor: badgeColor,
                  containerColor: badgeContainer,
                  leading: Icon(
                    isChange ? Icons.trending_down : Icons.trending_up,
                    size: 14,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: JournalSpacing.x3),
          Text(pattern.narrativeText, style: JournalType.prose),
          const SizedBox(height: JournalSpacing.x3),
          _StrengthPanel(pattern: pattern),
          // Where a number could not be computed, the reason takes its
          // place.
          if (pattern.comparisonNote case final note?) ...[
            const SizedBox(height: JournalSpacing.x3),
            _PatternNote(text: note),
          ],
          if (pattern.historicalNote case final note?) ...[
            const SizedBox(height: JournalSpacing.x3),
            _PatternNote(text: note, icon: Icons.history),
          ],
          // A confounder annotates a pattern, it never hides one --
          // withholding the evidence would contradict the app's own reason
          // for existing.
          for (final confounder in pattern.confounders) ...[
            const SizedBox(height: JournalSpacing.x3),
            _PatternNote(
              text: confounder.note,
              icon: Icons.link,
              container: theme.colorScheme.primaryContainer,
            ),
          ],
          // P0-6: no badge means no tip either. Advice to keep or change something is exactly
          // what a badge-less card has nothing to back -- whether because the feeling is neutral
          // (P0-2) or, as of P0-6, because the lift behind it is undefined or too weak to trust.
          // The counts and the narrative above still stand; only the advisory strip goes quiet.
          if (badge != null) ...[
            const SizedBox(height: JournalSpacing.x3),
            _SuggestionBlock(text: pattern.suggestionText),
          ],
          const SizedBox(height: JournalSpacing.x3),
          DecoratedBox(
            decoration: BoxDecoration(color: journal.hairline),
            child: const SizedBox(width: double.infinity, height: 1),
          ),
          const SizedBox(height: JournalSpacing.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Eyebrow(_footerText(pattern, widget.constants))),
              TextButton.icon(
                onPressed: () => setState(() => _showEvidence = !_showEvidence),
                icon: Icon(
                  _showEvidence ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(
                  _showEvidence
                      ? 'Hide entries'
                      : '${pattern.evidence.length} entries',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
          if (_showEvidence)
            _EvidenceTrail(
              pattern: pattern,
              recencyWindowDays: widget.constants.recencyWindowDays,
              onOpen: widget.onOpenEntry,
            ),
        ],
      ),
    );
  }
}

String _footerText(Pattern pattern, EngineConstants constants) {
  final times = pattern.occurrenceCount == 1 ? 'time' : 'times';
  final buffer = StringBuffer(
    '${pattern.occurrenceCount} $times in ${constants.recencyWindowDays} days',
  );
  if (pattern.lifetimeCount != pattern.occurrenceCount) {
    buffer.write(' · ${pattern.lifetimeCount} in total');
  }
  return buffer.toString();
}

/// The four figures every pattern states, as a 2x2 grid rather than prose --
/// the comparison is the entire point, and a sentence makes the reader hold
/// three numbers in their head to make it.
class _StrengthPanel extends StatelessWidget {
  const _StrengthPanel({required this.pattern});

  final Pattern pattern;

  @override
  Widget build(BuildContext context) {
    final isInverse = pattern.kind == PatternKind.inverse;
    final topic = pattern.topic;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JournalSpacing.x4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: JournalShapes.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: isInverse ? 'Without $topic' : 'With $topic',
                  value: _percentOrDash(pattern.presentRate),
                  detail: '${pattern.presentCount}/${pattern.presentTotal}',
                ),
              ),
              const SizedBox(width: JournalSpacing.x4),
              Expanded(
                child: _Stat(
                  label: isInverse ? 'With $topic' : 'Without $topic',
                  value: _percentOrDash(pattern.absentRate),
                  detail: '${pattern.absentCount}/${pattern.absentTotal}',
                ),
              ),
            ],
          ),
          const SizedBox(height: JournalSpacing.x2),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Usual rate',
                  value: _percentOrDash(pattern.baseRate),
                ),
              ),
              const SizedBox(width: JournalSpacing.x4),
              Expanded(
                child: _Stat(
                  label: 'Lift',
                  // An em dash, never "0.0×". A lift that could not be
                  // computed is not a small one, and printing a number here
                  // would invent the one figure the design forbids.
                  value: switch (pattern.lift) {
                    null => '—',
                    final lift => '${lift.toStringAsFixed(1)}×',
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label),
        const SizedBox(height: JournalSpacing.x1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail case final detail?) ...[
              const SizedBox(width: JournalSpacing.x2),
              Text(detail, style: theme.textTheme.labelSmall),
            ],
          ],
        ),
      ],
    );
  }
}

/// A dash for a rate that could not be computed, never `0%`.
String _percentOrDash(double? rate) => switch (rate) {
  null => '—',
  final rate => '${(rate * 100).round()}%',
};

class _PatternNote extends StatelessWidget {
  const _PatternNote({required this.text, this.icon, this.container});

  final String text;
  final IconData? icon;
  final Color? container;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: JournalSpacing.x3,
        vertical: JournalSpacing.x3,
      ),
      decoration: BoxDecoration(
        color: container ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: JournalShapes.small,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon case final icon?) ...[
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: JournalSpacing.x2),
          ],
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Advice rather than fact, so it is set apart and tinted with the advisory
/// accent.
class _SuggestionBlock extends StatelessWidget {
  const _SuggestionBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: journal.accentContainer,
        borderRadius: JournalShapes.medium,
        border: Border(left: BorderSide(color: journal.accent, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: JournalSpacing.x4,
          vertical: JournalSpacing.x3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb, size: 18, color: journal.accent),
            const SizedBox(width: JournalSpacing.x3),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

final DateFormat _evidenceDateFormat = DateFormat('d MMM');

/// The evidence trail: expands in place on the card, never by navigating
/// elsewhere.
class _EvidenceTrail extends StatelessWidget {
  const _EvidenceTrail({
    required this.pattern,
    required this.recencyWindowDays,
    required this.onOpen,
  });

  final Pattern pattern;
  final int recencyWindowDays;
  final void Function(String entryId, CalendarDate entryDate) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (pattern.evidence.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: JournalSpacing.x3),
        child: Text(
          'Nothing in the last $recencyWindowDays days. This pattern is '
          'built on older entries.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final entry in pattern.evidence)
          _EvidenceRow(
            entry: entry,
            onOpen: () => onOpen(entry.entryId, entry.entryDate),
          ),
      ],
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.entry, required this.onOpen});

  final PatternEvidence entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journal = context.journalColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: journal.hairline),
          child: const SizedBox(width: double.infinity, height: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: JournalSpacing.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      _evidenceDateFormat.format(entry.entryDate.toDateTime()),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.rawText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: 56,
                  top: JournalSpacing.x1,
                ),
                child: Wrap(
                  spacing: JournalSpacing.x2,
                  runSpacing: JournalSpacing.x1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final feeling in entry.feelings)
                      FeelingChip(
                        label: feeling.label,
                        color: feeling.accent(journal),
                      ),
                    TextButton(
                      onPressed: onOpen,
                      child: Text('Open', style: theme.textTheme.labelSmall),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
