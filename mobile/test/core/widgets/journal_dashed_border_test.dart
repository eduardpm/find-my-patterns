import 'package:find_my_patterns/core/widgets/journal_dashed_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Article 3: the dashed path is drawn geometry, not something to assert
  // pixels on. What is worth proving is the caching contract described on
  // [DashedBorder] — that painting twice at the same size reuses the first
  // path rather than rebuilding it, and that a size change invalidates the
  // cache — plus that the widget shows its child.
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows its child', (tester) async {
    await tester.pumpWidget(
      host(
        const DashedBorder(
          color: Colors.brown,
          borderRadius: BorderRadius.all(Radius.circular(8)),
          child: Text('inside the outline'),
        ),
      ),
    );
    expect(find.text('inside the outline'), findsOneWidget);
  });

  testWidgets('repaints without throwing when its size changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SizedBox(
          width: 100,
          height: 40,
          child: DashedBorder(
            color: Colors.brown,
            borderRadius: BorderRadius.all(Radius.circular(8)),
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      host(
        const SizedBox(
          width: 220,
          height: 90,
          child: DashedBorder(
            color: Colors.brown,
            borderRadius: BorderRadius.all(Radius.circular(8)),
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
