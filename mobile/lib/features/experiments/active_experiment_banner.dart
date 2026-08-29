import 'package:flutter/material.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/experiment.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/journal.dart';

/// "Experiment: more walking · day 3 of 7" — the slim banner Today shows
/// while an experiment is running (R-3b).
///
/// Placed directly under the day header, above the writing-streak line and
/// the first-week backdate nudge: an experiment is a live, time-bound
/// thing the reader chose to start and is counting down, which outranks
/// the two passive, always-eventually-true facts beneath it. It is also
/// the one thing on this crowded header a tap does something with, so it
/// reads first.
///
/// Stateless and given everything it needs, including [today] -- the day
/// count is arithmetic on dates that already exist
/// ([Experiment.dayNumber]), never a second call of its own.
class ActiveExperimentBanner extends StatelessWidget {
  /// Builds the banner for [experiment], read against [today].
  const ActiveExperimentBanner({
    super.key,
    required this.experiment,
    required this.today,
    required this.onTap,
  });

  /// The experiment currently running.
  final Experiment experiment;

  /// Today's date, for the "day N of length" count.
  final CalendarDate today;

  /// Called when the banner is tapped, to open the experiment's detail
  /// (the results screen, which reads "so far" while an experiment is
  /// still in progress).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journal = context.journalColors;
    final label = _label(experiment, today);
    return Semantics(
      label: '$label. Tap for detail.',
      button: true,
      child: ExcludeSemantics(
        child: JournalCard(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: JournalSpacing.x4,
            vertical: JournalSpacing.x3,
          ),
          child: Row(
            children: [
              Icon(Icons.science_outlined, size: 20, color: journal.accent),
              const SizedBox(width: JournalSpacing.x2),
              Expanded(
                child: Text(label, style: theme.textTheme.bodyMedium),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: journal.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Experiment: more walking · day 3 of 7".
///
/// The direction word ("more"/"less") comes from [Experiment.hypothesisKind]
/// -- the same hypothesis the setup sheet phrased when the experiment was
/// started -- never re-derived from the pattern's badge here.
String _label(Experiment experiment, CalendarDate today) {
  final direction = experiment.hypothesisKind == HypothesisKind.lessOf
      ? 'less'
      : 'more';
  return 'Experiment: $direction ${experiment.patternTopic} · '
      'day ${experiment.dayNumber(today)} of ${experiment.lengthDays}';
}
