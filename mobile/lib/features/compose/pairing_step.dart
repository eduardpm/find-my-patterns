import 'package:flutter/material.dart';

import '../../core/diary/entries_api.dart';
import '../../core/diary/entry.dart';
import '../../core/diary/feeling.dart';
import '../../core/diary/topic.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/widgets/feeling_accent.dart';
import '../../core/widgets/journal.dart';

/// Whether [entry]'s confirmed feelings span positive and negative valence.
///
/// This mirrors the backend's canonical rule -- `isMixedValence` in
/// `backend/src/insights/analysis.ts` (E-1b) -- exactly: neutral is its own
/// sign, never a wildcard that could tip a mix either way, so
/// positive+neutral is not mixed, negative+neutral is not mixed, and only
/// positive-and-negative together, in any company, counts. `mobile/CLAUDE.md`
/// says the backend owns the logic and this client only renders it; this
/// function is the one deliberate exception, because deciding whether to
/// *render* the pairing step at all has to happen the moment feelings are
/// confirmed, client-side, before any server round trip could echo the
/// verdict back. There is no shared payload field tying the two together --
/// keep this in sync with `isMixedValence` by hand if that rule ever
/// changes, and do not duplicate this check anywhere else in the widget
/// tree.
bool isMixedValenceEntry(Entry entry) {
  var hasPositive = false;
  var hasNegative = false;
  for (final feeling in entry.feelings) {
    if (feeling.valence == Valence.positive) hasPositive = true;
    if (feeling.valence == Valence.negative) hasNegative = true;
  }
  return hasPositive && hasNegative;
}

/// Whether [entry] should be routed through the "Which goes with what?"
/// pairing step (E-1c task 1) once its feelings are confirmed.
///
/// Both conditions are required: [isMixedValenceEntry], and at least two of
/// the entry's topics carry a pairing suggestion from the analyser
/// (`entry.topicFeelings`, E-1a). A single suggested pairing has nothing to
/// choose between, and an entry with none has nothing to show, so neither is
/// worth a step of its own. Most entries are single-valence and never reach
/// the second half of this check at all -- that is the point: this step is
/// friction only a mixed capture with something genuinely ambiguous ever
/// pays.
bool needsPairingStep(Entry entry) {
  if (!isMixedValenceEntry(entry)) return false;
  final suggestedTopicIds = {
    for (final pairing in entry.topicFeelings) pairing.topicId,
  };
  return suggestedTopicIds.length >= 2;
}

/// "Which goes with what?" -- E-1c's pairing sub-step.
///
/// Shown only between `ConfirmFeelingStage` and `EchoStage`, and only when
/// [needsPairingStep] says so: one row per confirmed feeling with its own
/// topics as chips underneath, pre-placed from the analyser's suggestion in
/// [Entry.topicFeelings], and a trailing "Not linked" row for every topic the
/// analyser did not (or the user has since unlinked). Tapping a chip cycles
/// it through every feeling row in order, then to "not linked", then back to
/// the first feeling -- see [_PairingStepState._next]. [onConfirm] hands back
/// every topic's *current* assignment, linked or not; [onSkip] is a plain
/// [VoidCallback] because skipping writes nothing at all -- see
/// [EntriesApi.setTopicFeelings]'s doc comment for why that must not be an
/// empty write.
class PairingStep extends StatefulWidget {
  /// Builds the pairing step for the just-confirmed [entry].
  const PairingStep({
    super.key,
    required this.entry,
    required this.isSaving,
    required this.onConfirm,
    required this.onSkip,
  });

  /// The entry whose [Entry.topics] and [Entry.topicFeelings] this reads.
  final Entry entry;

  /// True while a confirm or skip is in flight -- disables both actions the
  /// same way [PillButton]'s "Saving…" label does on the feeling-confirm
  /// step, so a second tap cannot fire a second request.
  final bool isSaving;

  /// Called with every topic's current assignment when "Confirm pairing" is
  /// pressed. A topic with no entry in the returned list was never
  /// reassigned away from "not linked".
  final void Function(List<TopicFeelingAssignment> pairings) onConfirm;

  /// Called when "Skip" is pressed. Writes nothing -- see the class doc.
  final VoidCallback onSkip;

  @override
  State<PairingStep> createState() => _PairingStepState();
}

class _PairingStepState extends State<PairingStep> {
  /// Topic id -> assigned feeling key. A topic with no entry here is "not
  /// linked". Seeded from the analyser's suggestion and touched only by
  /// [_cycle] afterwards -- a rebuild carrying the same entry (e.g.
  /// [PairingStep.isSaving] flipping while the confirm call is in flight)
  /// must never reset a reassignment the user already made.
  late Map<String, String> _assignments = _seedAssignments();

  Map<String, String> _seedAssignments() => {
    for (final pairing in widget.entry.topicFeelings)
      pairing.topicId: pairing.feeling.key,
  };

  @override
  void didUpdateWidget(covariant PairingStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entry.id != oldWidget.entry.id) {
      setState(() => _assignments = _seedAssignments());
    }
  }

  /// [current]'s next stop in the cycle: the feeling immediately after it in
  /// [feelings], `null` ("not linked") once the list runs out, and back to
  /// the first feeling from `null` -- so the cycle never dead-ends no matter
  /// how many feelings the entry carries.
  String? _next(String? current, List<Feeling> feelings) {
    if (feelings.isEmpty) return null;
    if (current == null) return feelings.first.key;
    final index = feelings.indexWhere((f) => f.key == current);
    if (index == -1 || index == feelings.length - 1) return null;
    return feelings[index + 1].key;
  }

  void _cycle(String topicId) {
    setState(() {
      final next = _next(_assignments[topicId], widget.entry.feelings);
      if (next == null) {
        _assignments = {..._assignments}..remove(topicId);
      } else {
        _assignments = {..._assignments, topicId: next};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journal = context.journalColors;
    final feelings = widget.entry.feelings;

    final byFeeling = <String, List<Topic>>{
      for (final feeling in feelings) feeling.key: [],
    };
    final unlinked = <Topic>[];
    for (final topic in widget.entry.topics) {
      final assignedKey = _assignments[topic.id];
      final bucket = assignedKey == null ? null : byFeeling[assignedKey];
      if (bucket != null) {
        bucket.add(topic);
      } else {
        unlinked.add(topic);
      }
    }

    final pairings = [
      for (final entry in _assignments.entries)
        (topicId: entry.key, feelingKey: entry.value),
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: JournalSpacing.x6),
          const Eyebrow('Saved'),
          const SizedBox(height: JournalSpacing.x1),
          Text('Which goes with what?', style: theme.textTheme.headlineSmall),
          const SizedBox(height: JournalSpacing.x2),
          Text(
            'This entry mixed good and hard feelings. Tap a topic to say '
            'which one it belongs with.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: JournalSpacing.x5),
          for (final feeling in feelings) ...[
            _PairingGroup(
              label: feeling.label,
              dotColor: feeling.accent(journal),
              topics: byFeeling[feeling.key] ?? const [],
              assignmentDescription: 'linked to ${feeling.label}',
              chipColor: feeling.accent(journal),
              onTapTopic: _cycle,
            ),
            const SizedBox(height: JournalSpacing.x4),
          ],
          _PairingGroup(
            label: 'Not linked',
            dotColor: theme.colorScheme.outline,
            topics: unlinked,
            assignmentDescription: 'not linked',
            chipColor: theme.colorScheme.onSurfaceVariant,
            onTapTopic: _cycle,
          ),
          const SizedBox(height: JournalSpacing.x5),
          Text(
            'Skipped pairings are never guessed — this entry won\'t count '
            'toward mixed patterns until you pair it.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: JournalSpacing.x4),
          SizedBox(
            width: double.infinity,
            child: PillButton(
              onPressed: !widget.isSaving
                  ? () => widget.onConfirm(pairings)
                  : null,
              child: Text(widget.isSaving ? 'Saving…' : 'Confirm pairing'),
            ),
          ),
          const SizedBox(height: JournalSpacing.x3),
          SizedBox(
            width: double.infinity,
            child: SecondaryPillButton(
              onPressed: !widget.isSaving ? widget.onSkip : null,
              child: const Text('Skip'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row: a feeling (or "Not linked") as a header, its topics as chips
/// underneath, in a [Wrap] so a long list -- or a large text scale -- wraps
/// rather than overflows.
class _PairingGroup extends StatelessWidget {
  const _PairingGroup({
    required this.label,
    required this.dotColor,
    required this.topics,
    required this.assignmentDescription,
    required this.chipColor,
    required this.onTapTopic,
  });

  final String label;
  final Color dotColor;
  final List<Topic> topics;

  /// What every chip in this row announces as its current assignment --
  /// "linked to Warm" or "not linked". Shared by every chip here because
  /// they are all, by construction, in the same bucket.
  final String assignmentDescription;
  final Color chipColor;
  final ValueChanged<String> onTapTopic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FeelingDot(color: dotColor),
            const SizedBox(width: JournalSpacing.x2),
            Flexible(child: Text(label, style: theme.textTheme.titleMedium)),
          ],
        ),
        const SizedBox(height: JournalSpacing.x3),
        if (topics.isEmpty)
          Text(
            'Nothing here yet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: JournalSpacing.x2,
            runSpacing: JournalSpacing.x2,
            children: [
              for (final topic in topics)
                _TopicPairingChip(
                  topic: topic,
                  color: chipColor,
                  assignmentDescription: assignmentDescription,
                  onTap: () => onTapTopic(topic.id),
                ),
            ],
          ),
      ],
    );
  }
}

/// One topic chip: a dot and its name in [color], cycling assignment on tap.
///
/// Modelled on `FeelingChip`'s pill (`core/widgets/feeling_chips.dart`) --
/// same dot-plus-label shape, same ≥44pt [BoxConstraints], same
/// [JournalShapes.full] pill -- but not built from it: `FeelingChip` toggles
/// a feeling in or out of a multi-select set and announces "select" /
/// "remove", whereas this chip cycles a topic through *every* feeling plus
/// "not linked" and must announce which one it landed on each time. Forcing
/// that onto `FeelingChip`'s boolean-selected contract would need a second,
/// unrelated mode bolted onto a widget that is about feelings, not topics --
/// a sibling with its own semantics is the smaller change.
///
/// [assignmentDescription] is read as this chip's semantics `value`, right
/// after [topic]'s name as its `label` -- "Parents, linked to Warm" end to
/// end -- so the assignment is a fact in the accessibility tree, never only
/// a position under a visual header. Because the same node stays focused
/// across a tap (the widget rebuilds in place; nothing steals focus), a
/// screen reader re-reads this `value` the moment it changes, which is what
/// actually announces the result of a cycle -- the same mechanism a
/// [Checkbox] or this app's own `_GroupChip` relies on for its own state.
class _TopicPairingChip extends StatelessWidget {
  const _TopicPairingChip({
    required this.topic,
    required this.color,
    required this.assignmentDescription,
    required this.onTap,
  });

  final Topic topic;
  final Color color;
  final String assignmentDescription;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = Container(
      constraints: const BoxConstraints(
        minHeight: JournalSpacing.x7,
        minWidth: JournalSpacing.x7,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: JournalSpacing.x4,
        vertical: JournalSpacing.x2,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: JournalShapes.full,
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FeelingDot(color: color),
          const SizedBox(width: JournalSpacing.x2),
          Text(
            topic.name,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: true,
      label: topic.name,
      value: assignmentDescription,
      onTapHint: 'change which feeling this is linked to',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const RoundedRectangleBorder(
              borderRadius: JournalShapes.full,
            ),
            child: chip,
          ),
        ),
      ),
    );
  }
}
