import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The warm wash painted down the top of every page: the palette's primary
/// container fading to nothing over roughly the first screenful.
///
/// Meant to sit at the bottom of a [Stack], behind scrolling content —
/// `Positioned.fill(child: JournalPageWash())` under a `CustomScrollView` or
/// `ListView`, for example — rather than as that content's background. Drawn
/// once at a fixed pixel height instead of scrolling with the list is what
/// makes it read as light falling on the page rather than as a banner
/// attached to the first item.
///
/// Purely decorative — there is nothing here for a screen reader to
/// announce — so it excludes itself from the semantics tree.
class JournalPageWash extends StatelessWidget {
  /// Paints the wash, fading out over [height] logical pixels.
  const JournalPageWash({super.key, this.height = 900});

  /// How far down the page the wash fades to nothing.
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.infinite,
      painter: _PageWashPainter(
        color: context.journalColors.primaryContainer,
        height: height,
      ),
    ),
  );
}

class _PageWashPainter extends CustomPainter {
  const _PageWashPainter({required this.color, required this.height});

  final Color color;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, height);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color, color.withValues(alpha: 0)],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _PageWashPainter oldDelegate) =>
      color != oldDelegate.color || height != oldDelegate.height;
}
