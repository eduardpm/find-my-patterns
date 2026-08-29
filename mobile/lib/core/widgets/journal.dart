import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/journal_metrics.dart';
import '../theme/journal_typography.dart';
import 'journal_dashed_border.dart';

/*
 * The shared vocabulary, ported from the web client's stylesheet so the two
 * clients read as one product: the eyebrow above a title, the paper card,
 * the pill button, the dashed empty state, the feeling dot.
 *
 * These are design-system primitives. Where the web fixes a value in CSS —
 * an eyebrow is always upper-cased and tracked, a dot is always round — the
 * parameter stays fixed here too, so a caller cannot quietly produce a
 * differently-shaped one. Regions the web leaves to page markup are slots.
 */

/// The tracked, upper-cased label that sits above a title or beside a time.
///
/// Primitive by design: every eyebrow in the app is meant to look identical,
/// and the upper-casing is display-only. [text] reaches the accessibility
/// tree in its own casing — [ExcludeSemantics] hides the shouted [Text] from
/// the tree entirely, and the surrounding [Semantics] supplies [text]
/// unchanged, so a screen reader announces the words a person actually
/// wrote rather than a wall of capitals.
class Eyebrow extends StatelessWidget {
  /// Shows [text] as an eyebrow, upper-cased for display only.
  const Eyebrow(this.text, {super.key, this.color});

  /// The label, in its natural casing.
  final String text;

  /// The text colour, or the theme's `onSurfaceVariant` if omitted.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Text(
          JournalType.eyebrowCase(text),
          style: JournalType.eyebrow.copyWith(color: resolvedColor),
        ),
      ),
    );
  }
}

/// A page's title block: an optional [eyebrow], the [title], and a row of
/// [actions], closed by the hairline rule the web draws under every page
/// header.
class PageHeader extends StatelessWidget {
  /// Builds a page header for [title].
  const PageHeader({
    super.key,
    this.eyebrow,
    required this.title,
    this.actions,
  });

  /// The label shown above [title], typically an [Eyebrow].
  final Widget? eyebrow;

  /// The page's title.
  final Widget title;

  /// Buttons or icons shown beside the title, spaced [JournalSpacing.x2]
  /// apart.
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final hairline = context.journalColors.hairline;
    final actionWidgets = actions;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          eyebrow!,
          const SizedBox(height: JournalSpacing.x1),
        ],
        title,
        if (actionWidgets != null && actionWidgets.isNotEmpty) ...[
          const SizedBox(height: JournalSpacing.x4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actionWidgets.length; i++) ...[
                if (i > 0) const SizedBox(width: JournalSpacing.x2),
                actionWidgets[i],
              ],
            ],
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: JournalSpacing.x4),
          child: SizedBox(
            width: double.infinity,
            height: 1,
            child: ColoredBox(color: hairline),
          ),
        ),
      ],
    );
  }
}

/// The paper card: a raised container on the page wash, bounded by a
/// hairline rather than by a shadow alone.
///
/// [onTap] is nullable because most cards are not tappable; passing one
/// adds the ink response and the tap semantics without changing anything
/// visual.
class JournalCard extends StatelessWidget {
  /// Wraps [child] in the card surface.
  const JournalCard({
    super.key,
    this.onTap,
    this.contentPadding = const EdgeInsets.all(JournalSpacing.x5),
    required this.child,
  });

  /// Called when the card is tapped, or `null` for a card that is not
  /// interactive.
  final VoidCallback? onTap;

  /// The padding around [child]. Defaults to [JournalSpacing.x5] on every
  /// side.
  final EdgeInsetsGeometry contentPadding;

  /// The card's content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hairline = context.journalColors.hairline;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: JournalShapes.large,
        border: Border.all(color: hairline),
      ),
      child: ClipRRect(
        borderRadius: JournalShapes.large,
        child: Material(
          color: theme.colorScheme.surfaceContainer,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: contentPadding, child: child),
          ),
        ),
      ),
    );
  }
}

/// The primary pill button: stadium-shaped, at least 48 logical pixels
/// tall, filled with the theme's `primary`/`onPrimary` pair.
///
/// [child] is a slot rather than a fixed label so an icon-plus-text caller
/// can lay its own children out, matching [ElevatedButton]'s own contract.
class PillButton extends StatelessWidget {
  /// Builds a primary pill button.
  const PillButton({super.key, required this.onPressed, required this.child});

  /// Called when the button is pressed, or `null` to disable it.
  final VoidCallback? onPressed;

  /// The button's content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        disabledBackgroundColor: colors.primary.withValues(alpha: 0.38),
        disabledForegroundColor: colors.onPrimary.withValues(alpha: 0.38),
        minimumSize: const Size(0, JournalSpacing.x7),
        shape: const RoundedRectangleBorder(borderRadius: JournalShapes.full),
        padding: const EdgeInsets.symmetric(
          horizontal: JournalSpacing.x5,
          vertical: JournalSpacing.x2,
        ),
      ),
      child: child,
    );
  }
}

/// The secondary pill: the same stadium shape as [PillButton], outlined on
/// the card surface, for actions that are not the point.
class SecondaryPillButton extends StatelessWidget {
  /// Builds a secondary pill button.
  const SecondaryPillButton({
    super.key,
    required this.onPressed,
    required this.child,
  });

  /// Called when the button is pressed, or `null` to disable it.
  final VoidCallback? onPressed;

  /// The button's content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: colors.surfaceContainer,
        foregroundColor: colors.onSurface,
        side: BorderSide(color: colors.outline),
        minimumSize: const Size(0, JournalSpacing.x7),
        shape: const RoundedRectangleBorder(borderRadius: JournalShapes.full),
        padding: const EdgeInsets.symmetric(
          horizontal: JournalSpacing.x5,
          vertical: JournalSpacing.x2,
        ),
      ),
      child: child,
    );
  }
}

/// The dashed-bordered empty state.
///
/// The dashed border is the point: it reads as a space waiting to be filled
/// rather than as a card that failed to load, and it distinguishes "nothing
/// here yet" from "something went wrong" without relying on the wording
/// alone.
class EmptyState extends StatelessWidget {
  /// Builds an empty state around [title].
  const EmptyState({
    super.key,
    this.icon,
    required this.title,
    this.supporting,
    this.action,
  });

  /// A small glyph shown in a circle above [title], or `null` for none.
  final Widget? icon;

  /// The empty state's headline.
  final Widget title;

  /// Supporting text shown under [title], or `null` for none.
  final Widget? supporting;

  /// A recovery action shown at the bottom, or `null` for none.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final body = <Widget>[
      if (icon != null)
        Container(
          width: JournalSpacing.x7,
          height: JournalSpacing.x7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.primaryContainer,
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: colors.primary),
            child: Center(child: icon),
          ),
        ),
      title,
      ?supporting,
    ];
    return DashedBorder(
      color: colors.outline,
      borderRadius: JournalShapes.large,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: JournalShapes.large,
          // The background reads as a hint rather than a filled surface, so
          // it never competes with the dashed outline for attention.
          color: colors.surfaceContainer.withValues(alpha: 0.55),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: JournalSpacing.x5,
            vertical: JournalSpacing.x7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < body.length; i++) ...[
                if (i > 0) const SizedBox(height: JournalSpacing.x3),
                body[i],
              ],
              if (action != null) ...[
                const SizedBox(height: JournalSpacing.x3 + JournalSpacing.x1),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A feeling's colour, as a dot.
///
/// Constrained on purpose: the colour comes from the feeling and the shape
/// never varies, so there is nothing here for a caller to decide beyond
/// size. It is decorative in every current use — the feeling is always
/// spelled out in words nearby — so it is hidden from the accessibility
/// tree.
class FeelingDot extends StatelessWidget {
  /// Paints a [size]-wide dot of [color].
  const FeelingDot({super.key, required this.color, this.size = 10});

  /// The dot's fill colour.
  final Color color;

  /// The dot's diameter.
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ),
  );
}

/// A bounded, upper-cased status pill — "KEEP DOING", "UNCONFIRMED".
class StatusBadge extends StatelessWidget {
  /// Builds a status badge showing [text].
  const StatusBadge(
    this.text, {
    super.key,
    this.contentColor,
    this.containerColor = Colors.transparent,
    this.leading,
  });

  /// The status text, upper-cased for display.
  final String text;

  /// The text and border colour, or the theme's `onSurfaceVariant` if
  /// omitted.
  final Color? contentColor;

  /// The badge's fill colour. Transparent by default.
  final Color containerColor;

  /// An icon shown before [text], inheriting [contentColor], or `null` for
  /// none.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        contentColor ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: JournalShapes.full,
        border: Border.all(color: resolvedColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: JournalSpacing.x3,
          vertical: JournalSpacing.x1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              IconTheme.merge(
                data: IconThemeData(color: resolvedColor),
                child: leading!,
              ),
              const SizedBox(width: JournalSpacing.x2),
            ],
            Text(
              JournalType.eyebrowCase(text),
              style: JournalType.eyebrow.copyWith(color: resolvedColor),
            ),
          ],
        ),
      ),
    );
  }
}
