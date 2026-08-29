import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/experiment.dart';
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
    this.activeExperiment,
    this.onTestPattern,
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

  /// The experiment currently running app-wide, if any (R-3b) -- used only
  /// to tell whether it is *this* card's own pattern, which swaps "Test
  /// this pattern" for "Experiment running". `null` while nothing is
  /// running, and also the default for a caller (or a test) that does not
  /// care about the experiments feature at all.
  final Experiment? activeExperiment;

  /// Called with [pattern] when "Test this pattern" is tapped, to open the
  /// setup sheet. `null` hides the action entirely -- point 1 of R-3b is
  /// offered from every card here, regardless of kind or status:
  /// eligibility is `POST /experiments`'s call, never re-derived on this
  /// card.
  final void Function(Pattern pattern)? onTestPattern;

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
      // UX-2: a strong card is meant to fit one screen. The default
      // padding is generous enough for a page-level surface, not for a
      // list of these stacked six deep -- shrinking it costs nothing a
      // reader needs, since the hairline border already separates one
      // card from the next.
      contentPadding: const EdgeInsets.all(JournalSpacing.x4),
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
          const SizedBox(height: JournalSpacing.x2),
          Text(pattern.narrativeText, style: JournalType.prose),
          const SizedBox(height: JournalSpacing.x2),
          _StrengthBars(pattern: pattern),
          // Where a number could not be computed, the reason takes its
          // place.
          if (pattern.comparisonNote case final note?) ...[
            const SizedBox(height: JournalSpacing.x2),
            _PatternNote(text: note),
          ],
          if (pattern.historicalNote case final note?) ...[
            const SizedBox(height: JournalSpacing.x2),
            _PatternNote(text: note, icon: Icons.history),
          ],
          // A confounder annotates a pattern, it never hides one --
          // withholding the evidence would contradict the app's own reason
          // for existing.
          for (final confounder in pattern.confounders) ...[
            const SizedBox(height: JournalSpacing.x2),
            _PatternNote(
              text: confounder.note,
              icon: Icons.link,
              container: theme.colorScheme.primaryContainer,
            ),
          ],
          const SizedBox(height: JournalSpacing.x2),
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
          // R-3b: "Test this pattern", or "Experiment running" when this
          // card's own topic/feeling is the one currently under test.
          // Appended at the end rather than woven into the sections above
          // so this stays a small, additive change.
          if (widget.onTestPattern case final onTestPattern?) ...[
            const SizedBox(height: JournalSpacing.x2),
            _ExperimentAction(
              isRunning:
                  widget.activeExperiment?.matches(
                    topic: pattern.topic,
                    feeling: pattern.feeling?.key,
                  ) ??
                  false,
              onTap: () => onTestPattern(pattern),
            ),
          ],
        ],
      ),
    );
  }
}

/// The bottom-of-card R-3b action: "Test this pattern", or a quiet
/// "Experiment running" badge in its place once this card's pattern is the
/// one being tested.
class _ExperimentAction extends StatelessWidget {
  const _ExperimentAction({required this.isRunning, required this.onTap});

  final bool isRunning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (isRunning) {
      return Align(
        alignment: Alignment.centerLeft,
        child: StatusBadge(
          'Experiment running',
          contentColor: Theme.of(context).colorScheme.primary,
          leading: const Icon(Icons.science_outlined, size: 14),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.science_outlined, size: 18),
        label: const Text('Test this pattern'),
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

/// Two horizontal bars on a shared 0-100% scale (CH-4), replacing the old
/// four-cell text grid: how often the feeling shows up with [Pattern.topic]
/// present, and how often it shows up without it. A reader parses two filled
/// bars against the same scale faster than four cells they have to hold in
/// their head and subtract to see the comparison the panel already knows.
///
/// The lift figure sits between the two bars, gated on [patternBadgeFor]
/// rather than on [Pattern.lift] directly (P0-6): the badge already
/// withholds itself for a null or below-threshold lift, or for a
/// neutral-valence feeling with nothing to say either way, and re-checking
/// the raw number here would be a second opinion about the same threshold
/// the backend already applied. [Pattern.lift] is still read, defensively,
/// once that gate is open -- so a payload that somehow paired a badge with
/// no lift number still renders instead of throwing.
class _StrengthBars extends StatelessWidget {
  const _StrengthBars({required this.pattern});

  final Pattern pattern;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journal = context.journalColors;
    final isInverse = pattern.kind == PatternKind.inverse;
    final topic = pattern.topic;
    final withLabel = isInverse ? 'Without $topic' : 'With $topic';
    final withoutLabel = isInverse ? 'With $topic' : 'Without $topic';
    final feelingLabel = pattern.feeling?.label.toLowerCase() ?? 'the feeling';
    // A neutral fallback for the rare pattern whose feeling did not resolve
    // through the catalog -- there is no valence to colour by, so the bar
    // reads as neither good nor bad news rather than guessing one.
    final fillColor =
        pattern.feeling?.accent(journal) ?? journal.feelings.steady;
    final trackColor = theme.colorScheme.onSurfaceVariant;
    final tickColor = theme.colorScheme.onSurface;
    final tickFraction = patternBarFraction(pattern.baseRate);
    final lift = patternBadgeFor(pattern) != null ? pattern.lift : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JournalSpacing.x3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: JournalShapes.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StrengthBar(
            label: withLabel,
            rate: pattern.presentRate,
            count: pattern.presentCount,
            total: pattern.presentTotal,
            tickFraction: tickFraction,
            fillColor: fillColor,
            trackColor: trackColor,
            tickColor: tickColor,
            semanticsSentence: _barSentence(
              withLabel,
              feelingLabel,
              pattern.presentCount,
              pattern.presentTotal,
              pattern.presentRate,
            ),
          ),
          const SizedBox(height: JournalSpacing.x2),
          // Undefined lift (P0-6): the explanation for *why* stays in
          // `comparisonNote`, rendered below this panel by `PatternCard`
          // itself -- this widget only ever omits the one figure it cannot
          // state, never a sentence explaining the omission.
          if (lift case final lift?) ...[
            Center(
              child: Text(
                '${lift.toStringAsFixed(1)}× more likely',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: JournalSpacing.x2),
          ],
          _StrengthBar(
            label: withoutLabel,
            rate: pattern.absentRate,
            count: pattern.absentCount,
            total: pattern.absentTotal,
            tickFraction: tickFraction,
            fillColor: fillColor,
            trackColor: trackColor,
            tickColor: tickColor,
            semanticsSentence: _barSentence(
              withoutLabel,
              feelingLabel,
              pattern.absentCount,
              pattern.absentTotal,
              pattern.absentRate,
            ),
          ),
          const SizedBox(height: JournalSpacing.x1),
          _UsualRateLegend(tickColor: tickColor, baseRate: pattern.baseRate),
        ],
      ),
    );
  }
}

/// One labeled bar: [Eyebrow] label, percent and exact count on their own
/// line (point 2 -- the counts are never dropped just because a bar already
/// draws the same ratio), then the bar itself.
///
/// The whole row collapses to one [semanticsSentence] (point 5) rather than
/// letting a screen reader piece the label, the percent and the count back
/// together as three separate stops.
class _StrengthBar extends StatelessWidget {
  const _StrengthBar({
    required this.label,
    required this.rate,
    required this.count,
    required this.total,
    required this.tickFraction,
    required this.fillColor,
    required this.trackColor,
    required this.tickColor,
    required this.semanticsSentence,
  });

  final String label;
  final double? rate;
  final int count;
  final int total;
  final double tickFraction;
  final Color fillColor;
  final Color trackColor;
  final Color tickColor;
  final String semanticsSentence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: semanticsSentence,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(label),
            const SizedBox(height: JournalSpacing.x1),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: JournalSpacing.x2,
              children: [
                Text(
                  _percentOrDash(rate),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text('$count/$total', style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: JournalSpacing.x1),
            _BarTrack(
              fraction: patternBarFraction(rate),
              tickFraction: tickFraction,
              fillColor: fillColor,
              trackColor: trackColor,
              tickColor: tickColor,
            ),
          ],
        ),
      ),
    );
  }
}

/// The bar itself: a rounded [trackColor] rail, filled from the left to
/// [fraction] in [fillColor], with a thin [tickColor] line marking
/// [tickFraction] -- the usual rate, so a reader can see at a glance whether
/// the fill lands above or below what this feeling does anyway, the same
/// comparison [Pattern.baseRate] exists to state.
///
/// A null rate and an undefined lift are drawn the same way an unmeasured
/// entry count is: as zero, never as a gap. [patternBarFraction] is what
/// turns "no rate" into 0.0 -- see its own doc comment for why 0% is
/// something this bar can draw rather than something it has to hide.
class _BarTrack extends StatelessWidget {
  const _BarTrack({
    required this.fraction,
    required this.tickFraction,
    required this.fillColor,
    required this.trackColor,
    required this.tickColor,
  });

  final double fraction;
  final double tickFraction;
  final Color fillColor;
  final Color trackColor;
  final Color tickColor;

  static const double _height = 10;
  static const double _tickWidth = 2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxLeft = (width - _tickWidth).clamp(0.0, double.infinity);
        final tickLeft = (width * tickFraction - _tickWidth / 2).clamp(
          0.0,
          maxLeft,
        );
        return SizedBox(
          height: _height,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: JournalShapes.full,
                ),
                child: const SizedBox(width: double.infinity, height: _height),
              ),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: JournalShapes.full,
                  ),
                  child: const SizedBox(height: _height),
                ),
              ),
              Positioned(
                left: tickLeft,
                child: ColoredBox(
                  color: tickColor,
                  child: const SizedBox(width: _tickWidth, height: _height),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The caption under both bars naming the tick's value in words -- the tick
/// alone only says "here", a sighted reader still has to know "here" means
/// [baseRate].
class _UsualRateLegend extends StatelessWidget {
  const _UsualRateLegend({required this.tickColor, required this.baseRate});

  final Color tickColor;
  final double baseRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ColoredBox(
          color: tickColor,
          child: const SizedBox(width: 2, height: 10),
        ),
        const SizedBox(width: JournalSpacing.x1),
        Text(
          'Usual rate: ${(baseRate * 100).round()}%',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The fill fraction a bar draws for [rate], clamped to 0..1.
///
/// A null rate -- the comparison could not be computed -- draws exactly like
/// a computed 0%: an empty bar, never a gap or a placeholder glyph. 0% is a
/// value this bar can draw; "unknown" is not, so the bar draws the nearest
/// honest thing and the text beside it (`_percentOrDash`) is what still
/// tells the reader the number itself was never known.
double patternBarFraction(double? rate) => (rate ?? 0.0).clamp(0.0, 1.0);

/// One sentence per bar (point 5): "With walking: calm in 3 of 6 entries, 50
/// percent" -- read whole by a screen reader instead of the label, the
/// percent and the count arriving as three separate stops.
String _barSentence(
  String label,
  String feelingLabel,
  int count,
  int total,
  double? rate,
) {
  final buffer = StringBuffer(
    '$label: $feelingLabel in $count of $total entries',
  );
  if (rate case final rate?) {
    buffer.write(', ${(rate * 100).round()} percent');
  }
  return buffer.toString();
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
