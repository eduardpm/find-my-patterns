/// @docImport '../widgets/journal.dart';
library;

import 'package:flutter/material.dart';

/// Corner radii, matching the web tokens' `--radius-*` scale.
///
/// A namespace of constants rather than an enum: nothing here is a closed set
/// a caller switches over, it is just a shared vocabulary of values so two
/// cards never quietly pick different roundedness.
abstract final class JournalShapes {
  /// The smallest radius: chips, small badges.
  static const BorderRadius small = BorderRadius.all(Radius.circular(6));

  /// The middle radius: inputs, secondary surfaces.
  static const BorderRadius medium = BorderRadius.all(Radius.circular(10));

  /// The card radius: [JournalCard] and [EmptyState] both use it, so a page
  /// full of cards reads as one shape language rather than several.
  static const BorderRadius large = BorderRadius.all(Radius.circular(16));

  /// A stadium/pill radius, for buttons and fully-rounded badges.
  ///
  /// Expressed as a very large circular radius rather than a distinct shape
  /// type so every [JournalShapes] member stays a [BorderRadius] and can be
  /// used interchangeably with `ClipRRect`, `BoxDecoration`, and
  /// `RoundedRectangleBorder` alike.
  static const BorderRadius full = BorderRadius.all(Radius.circular(999));
}

/// Spacing, matching the web client's 4px base scale.
///
/// A shared step size keeps the gap between an icon and a label, or a card's
/// content padding, the same value everywhere it is used rather than a new
/// guess at every call site.
abstract final class JournalSpacing {
  /// 4 logical pixels.
  static const double x1 = 4;

  /// 8 logical pixels.
  static const double x2 = 8;

  /// 12 logical pixels.
  static const double x3 = 12;

  /// 16 logical pixels.
  static const double x4 = 16;

  /// 24 logical pixels.
  static const double x5 = 24;

  /// 32 logical pixels.
  static const double x6 = 32;

  /// 48 logical pixels.
  static const double x7 = 48;
}
