import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../diary/feeling.dart';
import '../theme/app_theme.dart';
import '../theme/journal_metrics.dart';
import '../theme/journal_palette.dart';
import 'feeling_accent.dart';
import 'journal.dart';

/// Feeling selection, two levels deep.
///
/// The vocabulary is around thirty words in four groups — far more than fits
/// on a phone without turning the fastest step of writing an entry into a
/// scanning exercise. So **only the first level is ever on screen**: four
/// group chips, each opening that group's own words in a modal bottom
/// sheet. Picking "Tense" then "Overwhelmed" is two taps for a precision a
/// flat row of eight could not express at all.
///
/// A modal bottom sheet, not a dialog: the group's words belong within
/// thumb reach on a phone, and the platform sheet already handles the
/// scrim, drag-to-dismiss and the back gesture. Toggles inside, not a radio
/// group: an entry can carry several feelings, so the control is genuinely
/// multi-select. Colour by group, never by individual feeling: thirty
/// accents a reader can tell apart at chip size do not exist, four do, and
/// every feeling in a group shares that group's valence — see
/// `FeelingGroupAccent`/`FeelingAccent`.
///
/// A controlled widget: this owns no selection state of its own.
/// [selected] and [onSelectionChange] work the same way as, say, a
/// [TextField]'s `controller` — the caller is the source of truth, and this
/// widget only ever proposes a next value.
///
/// **A note on the sheet's own state.** [showModalBottomSheet]'s builder
/// runs in its own route and does not rebuild when this widget's parent
/// calls `setState` — the same trap the Kotlin original tripped on before
/// its `rememberUpdatedState` fix, where the sheet's tap handler closed
/// over the selection as it stood when the sheet opened, so every tap
/// computed `oldSelection + feeling` and the second word chosen from a
/// group replaced the first instead of joining it. This port's answer is a
/// [ValueNotifier] this state owns and keeps in sync with [selected] (see
/// `didUpdateWidget`); the sheet reads it through a [ValueListenableBuilder]
/// rather than closing over a plain list, so every tap — inside the sheet
/// or out — is decided against whatever is selected *now*.
class FeelingChips extends StatefulWidget {
  /// Builds the picker for [groups], the backend-served vocabulary.
  const FeelingChips({
    super.key,
    required this.groups,
    required this.selected,
    required this.onSelectionChange,
    this.suggestedKeys = const {},
    this.max = kMaxFeelingsPerEntry,
  });

  /// The backend-served vocabulary (`GET /feelings`), grouped. Empty while
  /// that fetch is in flight, in which case only the empty-state line and
  /// no group chips render.
  final List<FeelingGroup> groups;

  /// The feelings currently chosen for this entry.
  final List<Feeling> selected;

  /// Called with the next selection whenever the user adds or removes a
  /// feeling, in either the chosen-feelings row or a group's sheet.
  final ValueChanged<List<Feeling>> onSelectionChange;

  /// Keys the app suggested for this entry (from a prior transcription or
  /// guided flow), marked with a "suggested" label wherever they appear.
  final Set<String> suggestedKeys;

  /// The most feelings one entry may carry.
  final int max;

  @override
  State<FeelingChips> createState() => _FeelingChipsState();
}

class _FeelingChipsState extends State<FeelingChips> {
  late final ValueNotifier<List<Feeling>> _selectedNotifier = ValueNotifier(
    widget.selected,
  );

  @override
  void didUpdateWidget(covariant FeelingChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keeps the sheet's live view in sync with a `selected` the parent
    // changed for any reason — including a change that did not originate
    // from this widget's own [_toggle]. Deferred to after this frame:
    // setting the notifier here directly can land mid-build for a
    // `ValueListenableBuilder` that lives inside the sheet's own route (a
    // separate element tree this build pass is not visiting), which
    // Flutter forbids outright ("setState() called during build").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _selectedNotifier.value = widget.selected;
    });
  }

  @override
  void dispose() {
    _selectedNotifier.dispose();
    super.dispose();
  }

  /// Adds or removes [feeling], read against whatever is selected *right
  /// now* rather than whatever [FeelingChips.selected] happened to be when
  /// the caller (main row or sheet) was built. Called from both, so it is
  /// the one place the add/remove rule lives.
  void _toggle(Feeling feeling) {
    final current = _selectedNotifier.value;
    final alreadyChosen = current.any((f) => f.key == feeling.key);
    if (alreadyChosen) {
      widget.onSelectionChange([
        for (final f in current)
          if (f.key != feeling.key) f,
      ]);
    } else if (current.length < widget.max) {
      widget.onSelectionChange([...current, feeling]);
    }
  }

  void _openGroupSheet(FeelingGroup group) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        // Uncapped rather than the platform default's ~9/16-screen cap: a
        // group with many words, or a large accessibility text size, must
        // still fit without truncating the sheet's own content.
        isScrollControlled: true,
        builder: (sheetContext) => _GroupSheet(
          group: group,
          selectedListenable: _selectedNotifier,
          suggestedKeys: widget.suggestedKeys,
          max: widget.max,
          onToggle: _toggle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    final selected = widget.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected.isEmpty)
          Text(
            'Nothing chosen yet — pick a group to see the feelings inside '
            'it.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: journal.onSurfaceVariant),
          )
        else
          _ChosenFeelings(
            selected: selected,
            suggestedKeys: widget.suggestedKeys,
            onRemove: _toggle,
            journal: journal,
          ),
        const SizedBox(height: JournalSpacing.x3),
        Divider(color: journal.hairline, height: 1),
        const SizedBox(height: JournalSpacing.x3),
        _GroupChips(
          groups: widget.groups,
          selected: selected,
          journal: journal,
          onOpen: _openGroupSheet,
        ),
        if (selected.length >= widget.max) ...[
          const SizedBox(height: JournalSpacing.x3),
          // A note rather than hiding the remaining groups: a control that
          // vanishes at the limit reads as broken, and the chips that can
          // still be *removed* are directly above.
          Text(
            "That's as many as one entry can carry. Remove one to choose "
            'another.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: journal.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// The chosen feelings, above the groups. Once a sheet closes this row is
/// the only place the answer is visible, so nobody should have to reopen
/// four sheets to remember what they picked. Each entry is removable in
/// place.
class _ChosenFeelings extends StatelessWidget {
  const _ChosenFeelings({
    required this.selected,
    required this.suggestedKeys,
    required this.onRemove,
    required this.journal,
  });

  final List<Feeling> selected;
  final Set<String> suggestedKeys;
  final ValueChanged<Feeling> onRemove;
  final JournalColors journal;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: JournalSpacing.x2,
    runSpacing: JournalSpacing.x2,
    children: [
      for (final feeling in selected)
        _ChosenFeelingChip(
          feeling: feeling,
          suggested: suggestedKeys.contains(feeling.key),
          onRemove: () => onRemove(feeling),
          journal: journal,
        ),
    ],
  );
}

/// One removable chip in the chosen-feelings row.
class _ChosenFeelingChip extends StatelessWidget {
  const _ChosenFeelingChip({
    required this.feeling,
    required this.suggested,
    required this.onRemove,
    required this.journal,
  });

  final Feeling feeling;
  final bool suggested;
  final VoidCallback onRemove;
  final JournalColors journal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = feeling.accent(journal);
    return Semantics(
      // Its own boundary, or this chip's label would merge with its
      // neighbours' into one node.
      container: true,
      button: true,
      // The visible content reads as the word itself; the control's job is
      // removal, so that is the hint rather than the name — "Grateful,
      // button, double tap to remove" — without losing the word the chip
      // is actually about.
      label: feeling.label,
      onTapHint: 'remove',
      onTap: onRemove,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onRemove,
            customBorder: const RoundedRectangleBorder(
              borderRadius: JournalShapes.full,
            ),
            child: Container(
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
                color: accent.withValues(alpha: 0.12),
                borderRadius: JournalShapes.full,
                border: Border.all(color: accent, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FeelingDot(color: accent),
                  const SizedBox(width: JournalSpacing.x2),
                  Text(
                    feeling.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (suggested) ...[
                    const SizedBox(width: JournalSpacing.x2),
                    Text('suggested', style: theme.textTheme.labelSmall),
                  ],
                  const SizedBox(width: JournalSpacing.x2),
                  // Decoration beside a control whose action is already
                  // spoken by the wrapping [Semantics]; the whole visual
                  // subtree is already excluded above, so this needs no
                  // exclusion of its own.
                  Text('×', style: theme.textTheme.labelLarge),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The group chips, wrapped.
class _GroupChips extends StatelessWidget {
  const _GroupChips({
    required this.groups,
    required this.selected,
    required this.journal,
    required this.onOpen,
  });

  final List<FeelingGroup> groups;
  final List<Feeling> selected;
  final JournalColors journal;
  final ValueChanged<FeelingGroup> onOpen;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: JournalSpacing.x2,
    runSpacing: JournalSpacing.x2,
    children: [
      for (final group in groups)
        _GroupChip(
          group: group,
          chosenCount: group.feelings
              .where((f) => selected.any((s) => s.key == f.key))
              .length,
          journal: journal,
          onOpen: () => onOpen(group),
        ),
    ],
  );
}

/// One group chip.
///
/// A group with something chosen in it is marked **three ways** — heavier
/// border, tinted fill and the group's own colour — plus the count badge,
/// so it survives greyscale and colour blindness; colour is never the only
/// channel.
class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.group,
    required this.chosenCount,
    required this.journal,
    required this.onOpen,
  });

  final FeelingGroup group;
  final int chosenCount;
  final JournalColors journal;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = group.accent(journal);
    final active = chosenCount > 0;
    return Semantics(
      container: true,
      button: true,
      // A state rather than a rewritten name — "Uplifted, 2 chosen" keeps
      // the group's own word first, which is what the user is looking for.
      label: group.label,
      value: active ? '$chosenCount chosen' : null,
      onTap: onOpen,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            customBorder: const RoundedRectangleBorder(
              borderRadius: JournalShapes.full,
            ),
            child: Container(
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
                color: active
                    ? accent.withValues(alpha: 0.12)
                    : theme.colorScheme.surfaceContainer,
                borderRadius: JournalShapes.full,
                border: Border.all(
                  color: active ? accent : theme.colorScheme.outline,
                  width: active ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FeelingDot(color: accent),
                  const SizedBox(width: JournalSpacing.x2),
                  Text(
                    group.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: active ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  if (active) ...[
                    const SizedBox(width: JournalSpacing.x2),
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent,
                      ),
                      // Already spoken as the chip's own `value`; left in
                      // the tree it would be read a second time.
                      child: Text(
                        '$chosenCount',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.surface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One group's words, in a modal sheet.
///
/// Reads [selectedListenable] through a [ValueListenableBuilder] rather
/// than taking a plain `selected` list, so it repaints on every toggle even
/// though [showModalBottomSheet] hosts it in a route the parent's
/// `setState` does not reach. See the [FeelingChips] doc comment.
class _GroupSheet extends StatelessWidget {
  const _GroupSheet({
    required this.group,
    required this.selectedListenable,
    required this.suggestedKeys,
    required this.max,
    required this.onToggle,
  });

  final FeelingGroup group;
  final ValueListenable<List<Feeling>> selectedListenable;
  final Set<String> suggestedKeys;
  final int max;
  final ValueChanged<Feeling> onToggle;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    return SafeArea(
      // A scroll view rather than trusting the sheet's own height: a group
      // with many words, or a large accessibility text size, must still
      // fit rather than overflow.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(JournalSpacing.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.label,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: JournalSpacing.x2),
              Text(
                'Choose as many as fit. Tap one again to remove it.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: journal.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: JournalSpacing.x3),
              ValueListenableBuilder<List<Feeling>>(
                valueListenable: selectedListenable,
                builder: (context, selected, _) => Wrap(
                  spacing: JournalSpacing.x2,
                  runSpacing: JournalSpacing.x2,
                  children: [
                    for (final feeling in group.feelings)
                      _FeelingSheetChip(
                        feeling: feeling,
                        selected: selected.any((f) => f.key == feeling.key),
                        suggested: suggestedKeys.contains(feeling.key),
                        // Only unchosen chips go dead at the limit: the way
                        // back under it must stay open from inside the
                        // sheet the user is standing in.
                        enabled:
                            selected.any((f) => f.key == feeling.key) ||
                            selected.length < max,
                        onToggle: () => onToggle(feeling),
                        journal: journal,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: JournalSpacing.x4),
              SizedBox(
                width: double.infinity,
                child: PillButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One feeling inside a group's sheet.
///
/// A checkbox, not a radio: an entry carries several feelings, so this is
/// genuinely multi-select and must announce as such rather than as one
/// exclusive choice.
class _FeelingSheetChip extends StatelessWidget {
  const _FeelingSheetChip({
    required this.feeling,
    required this.selected,
    required this.suggested,
    required this.enabled,
    required this.onToggle,
    required this.journal,
  });

  final Feeling feeling;
  final bool selected;
  final bool suggested;
  final bool enabled;
  final VoidCallback onToggle;
  final JournalColors journal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = feeling.accent(journal);
    return Semantics(
      container: true,
      checked: selected,
      enabled: enabled,
      label: feeling.label,
      onTap: enabled ? onToggle : null,
      child: ExcludeSemantics(
        child: Opacity(
          // Dimmed *and* genuinely non-toggleable, so touch and a screen
          // reader learn the same thing.
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onToggle : null,
              customBorder: const RoundedRectangleBorder(
                borderRadius: JournalShapes.full,
              ),
              child: Container(
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
                  color: selected
                      ? accent.withValues(alpha: 0.12)
                      : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: JournalShapes.full,
                  border: Border.all(
                    color: selected ? accent : theme.colorScheme.outline,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FeelingDot(color: accent),
                    const SizedBox(width: JournalSpacing.x2),
                    Text(
                      feeling.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                    if (suggested) ...[
                      const SizedBox(width: JournalSpacing.x2),
                      Text('suggested', style: theme.textTheme.labelSmall),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
