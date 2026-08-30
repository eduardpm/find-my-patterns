import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/journal_metrics.dart';
import '../../core/theme/journal_palette.dart';
import '../../core/theme/journal_typography.dart';
import '../../core/widgets/journal.dart';

/// The paper this diary is written on, and whether it is lit or dark.
///
/// Ported from the Kotlin `AppearanceCard`. It lives in Settings rather than
/// behind a switch in the app's chrome for the same reason the topic editor
/// does: a paper is chosen once and then lived with, and a control in the
/// chrome would ask about it on every visit. Nothing here leaves the phone —
/// [SettingsController.savePalette] and [SettingsController.saveThemeMode]
/// only ever write to local storage.
///
/// Watches [settingsProvider] directly rather than holding a local copy of
/// the choice: the whole app themes itself from the same provider, so a tap
/// here has to leave this card and the app's theme agreeing. A snapshot in
/// local state would let the two drift apart the first time a save failed.
class AppearanceCard extends ConsumerWidget {
  /// Creates the appearance card.
  const AppearanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final notifier = ref.read(settingsProvider.notifier);

    return JournalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Appearance', style: theme.textTheme.titleMedium),
          const SizedBox(height: JournalSpacing.x2),
          Text(
            'Three papers to write on, each with a light and a dark half. '
            'The choice is kept on this phone.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: JournalSpacing.x5),
          const _GroupLabel('Light or dark'),
          const SizedBox(height: JournalSpacing.x3),
          _ModeSelector(
            mode: settings.themeMode,
            onChanged: (mode) => unawaited(notifier.saveThemeMode(mode)),
          ),
          const SizedBox(height: JournalSpacing.x5),
          const _GroupLabel('Paper'),
          const SizedBox(height: JournalSpacing.x3),
          _PaletteSelector(
            palette: settings.palette,
            onChanged: (palette) => unawaited(notifier.savePalette(palette)),
          ),
        ],
      ),
    );
  }
}

/// A group label that, unlike the shared `Eyebrow`, stays in the
/// accessibility tree.
///
/// Everywhere else in the app an eyebrow repeats context the title beside it
/// already carries, which is why `Eyebrow` clears its own semantics. These
/// two labels — "Light or dark" and "Paper" — are the only name the radio
/// group beneath them has: a screen reader needs to hear the group's name
/// before its options make sense, so this is a plain [Text] in the eyebrow
/// style rather than the self-silencing shared widget.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    JournalType.eyebrowCase(text),
    style: JournalType.eyebrow.copyWith(
      color: context.journalColors.onSurfaceVariant,
    ),
  );
}

/// One option in a single-choice radio group.
///
/// A screen reader should be told "Light, 2 of 3, selected" rather than
/// present three unrelated buttons whose relationship a person has to infer
/// from the layout — [Semantics]'s `inMutuallyExclusiveGroup` flag is what
/// carries that. The descendant [child] is excluded from the semantics tree
/// so its own text and icon are not announced a second time underneath this
/// node's [label].
class _RadioOption extends StatelessWidget {
  const _RadioOption({
    required this.selected,
    required this.label,
    required this.onSelect,
    required this.child,
  });

  final bool selected;
  final String label;
  final VoidCallback onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    selected: selected,
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onSelect,
    child: InkWell(onTap: onSelect, child: child),
  );
}

/// Three mutually exclusive options in one track: a phone for System, a sun
/// for Light, a moon for Dark — the trio every user has already learned
/// somewhere else.
///
/// **Measures the widest label once and lets that single decision drive all
/// three columns identically** — the same shared-fit-decision shape
/// `calendar_screen.dart`'s `_WeekdayHeaderRow` (#155) uses for its seven
/// near-identical weekday columns. #150's own fix wrapped each label in its
/// own `Flexible`, which stops the classic thrown overflow but not the sweep's
/// silent word-break invariant: inside the real `SettingsScreen` (narrower
/// than #150's own bare-`Scaffold` test harness — `ListView` padding on top
/// of `JournalCard`'s own) "System" still needs 84.0px at the *default* text
/// scale while its column has only 50.7px, and `Flexible` cannot split one
/// word across two lines. Letting each column decide independently whether
/// *it* personally fits would produce the inconsistency
/// `_WeekdayHeaderRow`'s own doc comment warns about — one segment icon-only,
/// its neighbours still labelled — so this measures once, for all three
/// together, exactly as that row does.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final ThemeModeSetting mode;
  final ValueChanged<ThemeModeSetting> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hairline = context.journalColors.hairline;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: JournalShapes.full,
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(JournalSpacing.x1),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const columns = ThemeModeSetting.values;
            final gaps = (columns.length - 1) * JournalSpacing.x1;
            final columnWidth = (constraints.maxWidth - gaps) / columns.length;
            // The icon (16) plus the gap beside it (`JournalSpacing.x2`)
            // every column reserves before its own label ever starts.
            const iconChrome = 16.0 + JournalSpacing.x2;
            final scaler = MediaQuery.textScalerOf(context);
            final widestLabelWidth = columns
                .map(
                  (option) => _measureWidth(
                    option.label,
                    theme.textTheme.labelLarge,
                    scaler,
                  ),
                )
                .reduce(math.max);
            final labelsFit = widestLabelWidth <= columnWidth - iconChrome;
            return Row(
              children: [
                for (final option in columns) ...[
                  if (option != columns.first)
                    const SizedBox(width: JournalSpacing.x1),
                  Expanded(
                    child: _RadioOption(
                      selected: option == mode,
                      label: option.label,
                      onSelect: () => onChanged(option),
                      child: _ModeOptionContent(
                        option: option,
                        selected: option == mode,
                        showLabel: labelsFit,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ModeOptionContent extends StatelessWidget {
  const _ModeOptionContent({
    required this.option,
    required this.selected,
    required this.showLabel,
  });

  final ThemeModeSetting option;
  final bool selected;

  /// Whether this column's own label text fits its share of the track,
  /// decided once by `_ModeSelector` for every column together. `false`
  /// drops the visible label and shows the icon alone -- still fully
  /// accessible, since `_RadioOption`'s own `Semantics.label` (the option's
  /// full name) is what a screen reader announces regardless of what this
  /// widget paints.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      // 48: the Material minimum, and these are the smallest targets on the
      // page.
      constraints: const BoxConstraints(minHeight: JournalSpacing.x7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: JournalShapes.full,
        color: selected
            ? theme.colorScheme.surfaceContainer
            : Colors.transparent,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_modeIcon(option), size: 16, color: color),
          if (showLabel) ...[
            const SizedBox(width: JournalSpacing.x2),
            // `Flexible`, not a bare `Text`: keeps a label that *does* fit
            // its column from throwing a classic `RenderFlex` overflow on a
            // near-miss. It cannot, on its own, stop a single word from
            // breaking mid-character when the column is narrower than the
            // word itself -- that is what `_ModeSelector`'s own
            // `labelsFit` decision is for.
            Flexible(
              child: Text(
                option.label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

IconData _modeIcon(ThemeModeSetting mode) => switch (mode) {
  ThemeModeSetting.system => Icons.smartphone,
  ThemeModeSetting.light => Icons.light_mode,
  ThemeModeSetting.dark => Icons.dark_mode,
};

/// One row per [JournalPalette], not a grid of three tiles.
///
/// A phone is narrow enough that three side-by-side previews would each be a
/// thumbnail too small to judge a page tint by, and the description is what
/// tells the three apart when they are all quiet greys at a glance.
///
/// **Measures the widest single-word palette name once and lets that one
/// decision drive every row identically** — the same shape `_ModeSelector`
/// above uses, applied here to a column of rows instead of a row of columns.
/// Only single-word names are measured (`"Warm paper"` has a break point and
/// wraps normally, so it is never at risk of the invariant this guards
/// against, however wide it is unbroken) — mirroring exactly which labels
/// `dynamic_type_matrix.dart`'s `brokenWords` check itself considers
/// (`text.contains(RegExp(r'\s'))`). At 320dp/2x inside the real
/// `SettingsScreen` "Sage"/"Dusk" need 136.0px but the preview-plus-label
/// `Row` only left 124.0px — a name this short has no shorter form to fall
/// back to the way `_ModeSelector`'s label can drop to icon-only, so every
/// row instead stacks its preview above its text when the widest name would
/// not fit beside it.
class _PaletteSelector extends StatelessWidget {
  const _PaletteSelector({required this.palette, required this.onChanged});

  final JournalPalette palette;
  final ValueChanged<JournalPalette> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final singleWordNames = JournalPalette.values
            .map((option) => option.label)
            .where((label) => !label.contains(' '));
        final widestNameWidth = singleWordNames
            .map(
              (label) =>
                  _measureWidth(label, theme.textTheme.titleMedium, scaler),
            )
            .reduce(math.max);
        // `_PaletteRow`'s own `Padding` (x3, every side) plus the preview
        // (76 wide), the gap beside it (x4) and the checkmark a selected
        // row reserves (x2 gap + 20 icon) -- reserved here whichever row is
        // actually selected, so selecting a different palette can never by
        // itself flip every row's layout.
        const chrome =
            JournalSpacing.x3 * 2 +
            _PalettePreview.width +
            JournalSpacing.x4 +
            JournalSpacing.x2 +
            20.0;
        final stacked = widestNameWidth > constraints.maxWidth - chrome;
        return Column(
          children: [
            for (final option in JournalPalette.values) ...[
              if (option != JournalPalette.values.first)
                const SizedBox(height: JournalSpacing.x3),
              _PaletteRow(
                option: option,
                selected: option == palette,
                onSelect: () => onChanged(option),
                stacked: stacked,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.option,
    required this.selected,
    required this.onSelect,
    required this.stacked,
  });

  final JournalPalette option;
  final bool selected;
  final VoidCallback onSelect;

  /// Whether the preview and the label/description block must stack
  /// vertically instead of sharing one line -- decided once, for every row
  /// together, by [_PaletteSelector]. See its own doc comment.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journal = context.journalColors;
    final borderColor = selected ? theme.colorScheme.primary : journal.hairline;
    // Selection is marked by the border, the tick and the tinted name
    // together, so it survives greyscale — the same rule the feeling chips
    // follow.
    final labelColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    final preview = _PalettePreview(
      colors: option.colors(dark: journal.isDark),
    );
    final check = selected
        ? Icon(Icons.check, color: theme.colorScheme.primary, size: 20)
        : null;
    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          option.label,
          style: theme.textTheme.titleMedium?.copyWith(color: labelColor),
        ),
        const SizedBox(height: JournalSpacing.x1),
        Text(
          option.description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final content = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  preview,
                  if (check != null) ...[const Spacer(), check],
                ],
              ),
              const SizedBox(height: JournalSpacing.x3),
              textBlock,
            ],
          )
        : Row(
            children: [
              // The preview is drawn from the option's own colours, not the
              // current theme's, so what a person sees is the paper they are
              // about to get. It shows the half — light or dark — that the
              // app is currently on, since that is the half switching to it
              // would produce.
              preview,
              const SizedBox(width: JournalSpacing.x4),
              Expanded(child: textBlock),
              if (check != null) ...[
                const SizedBox(width: JournalSpacing.x2),
                check,
              ],
            ],
          );

    return _RadioOption(
      selected: selected,
      label: '${option.label}. ${option.description}',
      onSelect: onSelect,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: JournalShapes.medium,
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(JournalSpacing.x3),
          child: content,
        ),
      ),
    );
  }
}

/// A page, a card on it, two lines of prose, and the four feeling dots — the
/// app in miniature.
class _PalettePreview extends StatelessWidget {
  const _PalettePreview({required this.colors});

  final JournalColors colors;

  /// This preview's fixed width — named so [_PaletteSelector]'s own layout
  /// decision can read it rather than repeat the number.
  static const double width = 76;

  @override
  Widget build(BuildContext context) {
    final dots = [
      colors.feelings.uplifted,
      colors.feelings.steady,
      colors.feelings.tense,
      colors.feelings.low,
    ];
    return Container(
      width: width,
      height: 62,
      padding: const EdgeInsets.all(JournalSpacing.x2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: JournalShapes.small,
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PreviewLine(
                  color: colors.primary,
                  widthFraction: 0.6,
                  height: 4,
                ),
                const SizedBox(height: 3),
                _PreviewLine(
                  color: colors.onSurfaceVariant,
                  widthFraction: 1,
                  height: 3,
                ),
                const SizedBox(height: 3),
                _PreviewLine(
                  color: colors.onSurfaceVariant,
                  widthFraction: 0.75,
                  height: 3,
                ),
              ],
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < dots.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                FeelingDot(color: dots[i], size: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({
    required this.color,
    required this.widthFraction,
    required this.height,
  });

  final Color color;
  final double widthFraction;
  final double height;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: widthFraction,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: JournalShapes.full),
      child: SizedBox(height: height),
    ),
  );
}

/// The natural, unwrapped width [text] would render at in [style] under
/// [scaler] — the same question `calendar_screen.dart`'s own `_measureWidth`
/// asks for `_WeekdayHeaderRow`, asked here for `_ModeSelector`'s and
/// `_PaletteSelector`'s shared-fit decisions.
double _measureWidth(String text, TextStyle? style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();
  return painter.width;
}
