import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../diary/feeling.dart';
import '../theme/app_theme.dart';
import '../theme/journal_metrics.dart';
import '../theme/journal_palette.dart';
import 'feeling_accent.dart';
import 'journal.dart';

/// Which of the two ways a [FeelingChip] is used.
enum FeelingChipVariant {
  /// A feeling stated as fact: a dot, its label, and — where the caller
  /// supplies one — an intensity suffix, all in the feeling's own valence
  /// colour on an otherwise transparent pill. Nothing here responds to a
  /// tap. This is every screen that *shows* a feeling rather than lets one
  /// be picked: Today's day summary and entry cards, entry detail, and a
  /// pattern's evidence trail.
  display,

  /// A feeling offered as a choice: adds a selected/unselected state and,
  /// where [FeelingChip.removable] is set, a remove affordance instead of
  /// a toggle. This is what the composer and entry-detail editor pickers
  /// below are built from.
  selectable,
}

/// The one feeling chip every screen in the app draws.
///
/// Before this, the same fact — "this entry carries this feeling" — was
/// drawn three different ways depending on which screen it appeared on: an
/// outlined pill on Today, a flat tinted pill in entry detail, and a pill
/// with an **emoji** standing in for the dot in Insights' evidence trail —
/// the app's only emoji-as-icon. [FeelingChipVariant.display] is Today's own
/// pill, the one the design review called "the good variant": a transparent
/// fill, a [FeelingDot] and the label both in [color], and a matching 1px
/// border. Every display site now draws that pill and nothing else — no
/// emoji, no flat grey, no second visual language (see
/// `specs/research/unified-backlog.md` UX-5).
///
/// [color] is always resolved by the caller through
/// [FeelingAccent.accent]/[FeelingGroupAccent.accent], never picked here —
/// this widget draws whatever colour it is handed, so a screen with the
/// wrong palette lookup shows up as wrong colour, not as a different shape.
/// Both palette halves keep every feeling hue at a 4.5:1 text contrast (see
/// `journal_palette.dart`), so [color] is safe to paint as this chip's own
/// label text as well as its dot and border.
///
/// [FeelingChipVariant.selectable] adds the states a picker needs on top
/// of the same pill:
/// [selected] swaps the transparent fill for a lightly tinted one and
/// thickens the border, [suggested] appends a "suggested" note for a
/// feeling the analyser proposed rather than the user picked, and
/// [removable] swaps the toggle affordance for a trailing "×" and the
/// tap's accessibility hint from "select" to "remove" — see
/// [FeelingChips]'s own chosen-feelings row and group sheet, the two
/// places that set it.
class FeelingChip extends StatelessWidget {
  /// Builds a chip showing [label] in [color].
  const FeelingChip({
    super.key,
    required this.label,
    required this.color,
    this.variant = FeelingChipVariant.display,
    this.selected = false,
    this.suggested = false,
    this.enabled = true,
    this.removable = false,
    this.intensityLabel,
    this.onTap,
  }) : assert(
         variant == FeelingChipVariant.display || onTap != null,
         'A selectable FeelingChip needs an onTap.',
       );

  /// The feeling's own word, in its natural case — never upper-cased and
  /// never paired with an emoji.
  final String label;

  /// This chip's valence colour, resolved by the caller — see the class
  /// doc.
  final Color color;

  /// [FeelingChipVariant.display] (the default) or
  /// [FeelingChipVariant.selectable].
  final FeelingChipVariant variant;

  /// Whether this chip is the chosen one, for [FeelingChipVariant.selectable]
  /// only. Ignored by [FeelingChipVariant.display], which always paints as
  /// "on" — it has nothing to be unselected relative to.
  final bool selected;

  /// Whether to append a "suggested" note — the analyser proposed this
  /// feeling rather than the user picking it themselves.
  final bool suggested;

  /// Whether this chip can still be tapped, for
  /// [FeelingChipVariant.selectable] only — an unchosen chip goes
  /// non-interactive once a picker's limit is reached.
  final bool enabled;

  /// Shows a trailing "×" and announces the tap as "remove" instead of a
  /// toggle. Set on an already-chosen chip in a row of chosen feelings;
  /// left `false` for a chip that is still being chosen from, where the
  /// [selected] state itself is the only thing that changes on a tap.
  final bool removable;

  /// An optional suffix shown after [label] — "3 of 5" beside "Stressed" —
  /// for a screen carrying a per-feeling intensity. `null` shows no
  /// suffix at all, which is every current call site except entry detail.
  final String? intensityLabel;

  /// Called on a tap, for [FeelingChipVariant.selectable] only.
  final VoidCallback? onTap;

  bool get _selectable => variant == FeelingChipVariant.selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // "On" is what paints the chip in its own colour: a display chip
    // always is, because it is stating a fact rather than offering a
    // choice; a selectable chip only once it is the chosen one.
    final on = !_selectable || selected;
    final background = on
        ? color.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerHigh;
    // Transparent rather than tinted for a plain display chip -- Today's
    // own pill, the variant this whole widget is modelled on, was never
    // filled, only outlined.
    final resolvedBackground = _selectable ? background : Colors.transparent;
    final borderColor = on ? color : theme.colorScheme.outline;
    final borderWidth = _selectable && selected ? 2.0 : 1.0;
    final textColor = on ? color : theme.colorScheme.onSurface;
    final fontWeight = on ? FontWeight.bold : FontWeight.w500;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FeelingDot(color: color),
        const SizedBox(width: JournalSpacing.x2),
        // `Flexible` rather than a bare `Text`: two chips sharing a `Wrap`
        // row (the fix this file exists for, #111) means each one can be
        // offered less width than its longest word needs once a reader's
        // text scale is turned up -- "Affectionate" or "Disappointed" at
        // 2x can outgrow the space left after the dot and padding. `Row`
        // gives `Flexible`'s child the leftover width rather than its own
        // unbounded natural size, so the label wraps onto a second line
        // and the pill grows taller instead of painting past its own
        // border -- the label still reads in full, just never truncated
        // or clipped, which an `Expanded`/ellipsis would each have done.
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: textColor,
              fontWeight: fontWeight,
            ),
          ),
        ),
        if (intensityLabel case final intensityLabel?) ...[
          const SizedBox(width: JournalSpacing.x2),
          Text(
            intensityLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (suggested) ...[
          const SizedBox(width: JournalSpacing.x2),
          Text('suggested', style: theme.textTheme.labelSmall),
        ],
        if (removable) ...[
          const SizedBox(width: JournalSpacing.x2),
          Text(
            '×',
            style: theme.textTheme.labelLarge?.copyWith(color: textColor),
          ),
        ],
      ],
    );

    final chip = Container(
      constraints: _selectable
          ? const BoxConstraints(
              minHeight: JournalSpacing.x7,
              minWidth: JournalSpacing.x7,
            )
          : null,
      padding: const EdgeInsets.symmetric(
        horizontal: JournalSpacing.x4,
        vertical: JournalSpacing.x2,
      ),
      // No `alignment` here -- that was the whole defect (#111). A
      // `Container` with a non-null `alignment` inserts an `Align` that, for
      // any axis where the ambient constraints are bounded, sizes itself to
      // the *full* bound rather than to its child, because `Align` only
      // shrink-wraps an axis when that axis's incoming max is unbounded or
      // a width/heightFactor forces it to. Every call site here sits inside
      // a `Wrap`, which does give a bounded max width once a screen is
      // involved, so the chip claimed the whole row and the `Wrap` never
      // got a second chip to place beside it. Nothing here needs
      // `Container`'s own centring anyway: the `Row` above is already
      // `mainAxisSize: MainAxisSize.min`, so it is exactly as wide as its
      // contents, and `Padding` alone gives it equal insets on every side
      // -- with no slack between content and box, that already reads as
      // centred without any `Align` involved.
      //
      // The one place a size larger than the content can still appear is
      // the `_selectable` branch's `minWidth`/`minHeight` -- the 48dp tap
      // target, which is bigger than a short label like "Sad" plus its
      // padding. That gap still needs its content centred, but by an inner
      // `Center` with both factors pinned to 1 rather than by `Container`'s
      // `alignment`: a `widthFactor`/`heightFactor` of 1 forces `Align` to
      // shrink-wrap *regardless* of the ambient constraints' boundedness
      // (see `RenderPositionedBox._shrinkWrapWidth`/`_shrinkWrapHeight`),
      // so it only grows past the label's natural size to satisfy our own
      // `BoxConstraints.minWidth`/`minHeight` below it -- never to fill
      // whatever width the enclosing `Wrap` happens to have on offer.
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: JournalShapes.full,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: _selectable
          ? Center(widthFactor: 1, heightFactor: 1, child: content)
          : content,
    );

    if (!_selectable) return chip;

    return Semantics(
      // A removable (already-chosen) chip's job is removal, so that is the
      // tap action's hint rather than a rewritten name -- "Grateful,
      // button, double tap to remove" -- without losing the word the chip
      // is about. A still-being-chosen-from chip is genuinely multi-select,
      // so it announces as a checkbox instead of one exclusive choice.
      container: true,
      button: removable ? true : null,
      checked: removable ? null : selected,
      enabled: removable ? null : enabled,
      label: label,
      onTapHint: removable ? 'remove' : null,
      onTap: enabled ? onTap : null,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              customBorder: const RoundedRectangleBorder(
                borderRadius: JournalShapes.full,
              ),
              child: chip,
            ),
          ),
        ),
      ),
    );
  }
}

/// Feeling selection, one sheet deep.
///
/// The vocabulary is around thirty words in four groups — far more than fits
/// on a phone without turning the fastest step of writing an entry into a
/// scanning exercise, so the words themselves never sit on the main screen.
/// This used to also mean picking across groups (Stressed *and* Grateful,
/// the common mixed-feeling case) cost two full sheet round-trips — tap a
/// group chip, tap a word, tap Done, then repeat for the other group. All
/// 31 words fit, grouped under four headers, in one scrollable sheet, so
/// there is no reason to reopen it for a second group: a group chip now
/// opens **one shared sheet holding every group**, and cross-group
/// selection is just more taps inside a sheet that is already open.
///
/// The four group chips on the main screen stay, rather than being replaced
/// by a single "choose feelings" button, because [_GroupChip] carries a
/// chosen-count badge marked three ways (border, fill and the count itself)
/// so it survives greyscale and colour blindness — a real accessibility
/// property, not a cosmetic one, and collapsing to one affordance would
/// have nowhere to put it. Each chip still opens the shared sheet; tapping
/// one also scrolls the sheet to that group's own section, so the chip you
/// tapped is where your thumb lands. A tab/segmented-control-per-group
/// sheet was the issue's fallback design, but was not needed here — the
/// vocabulary is short enough that one scrollable list, not a second
/// navigation level, is the simpler answer.
///
/// A modal bottom sheet, not a dialog: the words belong within thumb reach
/// on a phone, and the platform sheet already handles the scrim,
/// drag-to-dismiss and the back gesture. Toggles inside, not a radio group:
/// an entry can carry several feelings, so the control is genuinely
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
/// group replaced the first instead of joining it. Folding every group into
/// one sheet makes this worse, not better, if left unfixed — a
/// cross-group pick is now two taps in the *same* open route instead of two
/// taps split across two routes, so the stale-closure bug would now eat the
/// very case this redesign exists for. This port's answer is a
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

  /// Opens the one shared sheet holding every group, scrolled to
  /// [initialGroup]'s own section — see the [FeelingChips] doc comment for
  /// why a single sheet replaced the old per-group one.
  void _openFeelingSheet(FeelingGroup initialGroup) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        // Uncapped rather than the platform default's ~9/16-screen cap: all
        // four groups, or a large accessibility text size, must still fit
        // without truncating the sheet's own content.
        isScrollControlled: true,
        // `showModalBottomSheet`'s own default (`useSafeArea: false`) does
        // not merely skip adding a safe area -- it actively strips the top
        // `MediaQuery` padding via `MediaQuery.removePadding(removeTop:
        // true)` before `_FeelingSheet` ever builds, on the assumption that
        // a bottom sheet never reaches the top of the screen (see that
        // parameter's own doc comment). This sheet is `isScrollControlled`
        // and uncapped, so at a tall vocabulary or a large text scale it
        // does reach the top -- and `_FeelingSheet`'s own `SafeArea` was a
        // provable no-op against padding that had already been zeroed out
        // upstream (see #150's PR for the widget test this proves red
        // against). `useSafeArea: true` keeps the top inset in the
        // `MediaQuery` `_FeelingSheet` reads instead of removing it, so its
        // own `SafeArea` has real padding to apply.
        useSafeArea: true,
        builder: (sheetContext) => _FeelingSheet(
          groups: widget.groups,
          initialGroup: initialGroup,
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
          onOpen: _openFeelingSheet,
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
        FeelingChip(
          label: feeling.label,
          color: feeling.accent(journal),
          variant: FeelingChipVariant.selectable,
          selected: true,
          suggested: suggestedKeys.contains(feeling.key),
          removable: true,
          onTap: () => onRemove(feeling),
        ),
    ],
  );
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

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FeelingDot(color: accent),
        const SizedBox(width: JournalSpacing.x2),
        // `Flexible` rather than a bare `Text`, for the same reason as
        // `FeelingChip` (#111): two group chips sharing a `Wrap` row can be
        // offered less width than a label needs at a high text scale, and
        // the count badge below eats into that width further whenever the
        // group is active. Group labels are short ("Uplifted" is the
        // longest), so this is a defensive match with `FeelingChip` rather
        // than a fix for an observed overflow here.
        Flexible(
          child: Text(
            group.label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
        if (active) ...[
          const SizedBox(width: JournalSpacing.x2),
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
            // Already spoken as the chip's own `value`; left in the tree it
            // would be read a second time.
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
    );

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
              // No `alignment` here -- this is the same defect #111 fixed on
              // `FeelingChip`, and this `Container` sits inside the very
              // same kind of `Wrap` (`_GroupChips`, above). A non-null
              // `alignment` inserts an `Align` that expands to the full
              // ambient bound on any axis with a finite max rather than
              // shrink-wrapping its child, so every group chip claimed a
              // whole row and the `Wrap` never got a second chip to place
              // beside it. Centring the content inside the `minWidth`/
              // `minHeight` tap target below is instead done with an inner
              // `Center` pinned to `widthFactor`/`heightFactor: 1`, which
              // shrink-wraps regardless of the ambient constraints'
              // boundedness and only grows past the content's natural size
              // to satisfy that minimum -- never to fill whatever width the
              // `Wrap` happens to offer. See `FeelingChip.build`'s own
              // comment on this same `Container` field for the full
              // `RenderPositionedBox` mechanics.
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
              child: Center(widthFactor: 1, heightFactor: 1, child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every group's words, in one shared modal sheet.
///
/// One title, one "Choose up to 4" line, then each group as its own section
/// — a coloured dot and the group's name as a header, that group's words in
/// a [Wrap] underneath. Sections replace the old per-group sheet's single
/// title; see the [FeelingChips] doc comment for why one sheet now holds
/// all four groups instead of one sheet per group.
///
/// Reads [selectedListenable] through a [ValueListenableBuilder] rather
/// than taking a plain `selected` list, so it repaints on every toggle even
/// though [showModalBottomSheet] hosts it in a route the parent's
/// `setState` does not reach — see the [FeelingChips] doc comment, which
/// also explains why that trap matters more now that a single sheet carries
/// every cross-group tap.
class _FeelingSheet extends StatelessWidget {
  const _FeelingSheet({
    required this.groups,
    required this.initialGroup,
    required this.selectedListenable,
    required this.suggestedKeys,
    required this.max,
    required this.onToggle,
  });

  final List<FeelingGroup> groups;

  /// The group whose chip was tapped to open this sheet. Not a filter —
  /// every group's words are here regardless — just where the sheet scrolls
  /// to on open, so the chip the user tapped is where their thumb lands.
  final FeelingGroup initialGroup;
  final ValueListenable<List<Feeling>> selectedListenable;
  final Set<String> suggestedKeys;
  final int max;
  final ValueChanged<Feeling> onToggle;

  @override
  Widget build(BuildContext context) {
    final journal = context.journalColors;
    final theme = Theme.of(context);
    // Built fresh on every `build` call together with the sections they are
    // attached to, so a key and the section it points at never drift apart
    // even on the rare rebuild (a dependency change, e.g. theme) that this
    // otherwise-static sheet gets.
    final sectionKeys = {
      for (final group in groups) group.key: GlobalKey(),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sectionContext = sectionKeys[initialGroup.key]?.currentContext;
      if (sectionContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            sectionContext,
            duration: const Duration(milliseconds: 200),
          ),
        );
      }
    });
    return SafeArea(
      // A scroll view rather than trusting the sheet's own height: four
      // groups' worth of words, or a large accessibility text size, must
      // still fit rather than overflow.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(JournalSpacing.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose feelings', style: theme.textTheme.headlineSmall),
              const SizedBox(height: JournalSpacing.x2),
              Text(
                'Choose up to $max. Tap one again to remove it.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: journal.onSurfaceVariant,
                ),
              ),
              for (final group in groups) ...[
                const SizedBox(height: JournalSpacing.x4),
                Row(
                  key: sectionKeys[group.key],
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    FeelingDot(color: group.accent(journal)),
                    const SizedBox(width: JournalSpacing.x2),
                    // `Flexible`, not a bare `Text`: a group heading is a
                    // short single word today, but at 2x text scale plus a
                    // narrow 320dp sheet plus the top status-bar inset this
                    // fix restores (see the `useSafeArea` change on
                    // `_openFeelingSheet`, above), even "Uplifted" alone can
                    // outgrow the row by a few pixels once the dot and gap
                    // are accounted for. Wrapping to a second line matches
                    // every other row on this card that is not allowed to
                    // clip a label (#111's own chips, right above).
                    Flexible(
                      child: Text(
                        group.label,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: JournalSpacing.x3),
                ValueListenableBuilder<List<Feeling>>(
                  valueListenable: selectedListenable,
                  builder: (context, selected, _) => Wrap(
                    spacing: JournalSpacing.x2,
                    runSpacing: JournalSpacing.x2,
                    children: [
                      for (final feeling in group.feelings)
                        FeelingChip(
                          label: feeling.label,
                          color: feeling.accent(journal),
                          variant: FeelingChipVariant.selectable,
                          selected: selected.any(
                            (f) => f.key == feeling.key,
                          ),
                          suggested: suggestedKeys.contains(feeling.key),
                          // Only unchosen chips go dead at the limit: the
                          // way back under it must stay open from inside
                          // the sheet the user is standing in.
                          enabled:
                              selected.any((f) => f.key == feeling.key) ||
                              selected.length < max,
                          onTap: () => onToggle(feeling),
                        ),
                    ],
                  ),
                ),
              ],
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
