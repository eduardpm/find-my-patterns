import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every string actually painted to the screen right now, flattened from
/// every [Text] in the tree -- plain or [Text.rich].
///
/// This is the sixth instance of one bug family (#108, #111, #115, #117,
/// #131, #137): a widget-tree assertion (`find.byType`, or checking a
/// widget's own constructor argument) proves a piece of text exists in the
/// *source*, never that its characters made it onto the *screen* at a
/// non-zero size, unclipped and untruncated. #137 is also the first of the
/// six where a single row can legitimately take either of two shapes
/// depending on measured width -- a plain `Text('12')` next to a plain
/// `Text('entries')` in the ordinary case, or one `Text.rich` spanning both
/// words when they must share a wrapped line -- so a test that only knows
/// how to find one shape would need its own assertion duplicated per
/// layout branch. Reading every `Text` (of either shape) into one flat
/// string sidesteps that: the caller asks "did this string end up on
/// screen" without caring which widget carried it.
///
/// Kept deliberately small rather than growing into a general geometry
/// toolkit -- #117 proposed the same kind of shared helper for chip
/// layout and this file does not attempt to unify with it or backfill
/// every other screen; it exists because #137 is the first ticket where a
/// single string can legitimately live in either widget shape, and that is
/// the one problem this function solves.
String renderedText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final widget in tester.allWidgets) {
    if (widget is! Text) continue;
    final data = widget.data;
    final span = widget.textSpan;
    if (data != null) buffer.write(data);
    if (span != null) buffer.write(span.toPlainText());
  }
  return buffer.toString();
}
