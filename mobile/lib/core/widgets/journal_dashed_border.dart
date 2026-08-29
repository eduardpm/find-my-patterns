/// @docImport 'journal.dart';
library;

import 'package:flutter/material.dart';

/// A dashed outline drawn around [child].
///
/// Flutter has no dashed equivalent of a plain [Border] the way the web
/// client's `border: 1px dashed` is built in, and [EmptyState] leans on one:
/// it is what makes "nothing here yet" look like a space waiting to be
/// filled rather than a card that failed to load.
///
/// The dash geometry is rebuilt only when the canvas size or the shape
/// parameters change rather than on every frame: [CustomPainter.paint]
/// compares the
/// incoming canvas size against the last one it drew and reuses the cached
/// [Path] when nothing has moved.
class DashedBorder extends StatelessWidget {
  /// Draws a dashed [color] outline of [borderRadius] around [child].
  const DashedBorder({
    super.key,
    required this.color,
    required this.borderRadius,
    this.strokeWidth = 1,
    this.dash = 6,
    this.gap = 5,
    required this.child,
  });

  /// The outline's colour.
  final Color color;

  /// The corner radius the dashed outline follows.
  final BorderRadius borderRadius;

  /// The outline's thickness.
  final double strokeWidth;

  /// The length of each dash.
  final double dash;

  /// The gap between two dashes.
  final double gap;

  /// The content the outline surrounds.
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _DashedBorderPainter(
      color: color,
      borderRadius: borderRadius,
      strokeWidth: strokeWidth,
      dash: dash,
      gap: gap,
    ),
    child: child,
  );
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    required this.borderRadius,
    required this.strokeWidth,
    required this.dash,
    required this.gap,
  });

  final Color color;
  final BorderRadius borderRadius;
  final double strokeWidth;
  final double dash;
  final double gap;

  Size? _cachedSize;
  Path? _cachedPath;

  Path _dashedOutline(Size size) {
    final cached = _cachedPath;
    if (cached != null && _cachedSize == size) return cached;

    final outline = Path()..addRRect(borderRadius.toRRect(Offset.zero & size));
    final dashed = Path();
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        dashed.addPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          Offset.zero,
        );
        distance = next + gap;
      }
    }
    _cachedSize = size;
    _cachedPath = dashed;
    return dashed;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _dashedOutline(size),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color ||
      borderRadius != oldDelegate.borderRadius ||
      strokeWidth != oldDelegate.strokeWidth ||
      dash != oldDelegate.dash ||
      gap != oldDelegate.gap;
}
