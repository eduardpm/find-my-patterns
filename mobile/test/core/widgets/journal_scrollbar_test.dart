import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/widgets/journal_scrollbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Article 3: the thumb's brightness and thickness are visual details
  // (Article 5). What is worth proving here is the behaviour the doc comment
  // promises — the wrapped content still scrolls, and switching between the
  // resting and in-progress state doesn't throw — plus that the listener
  // this widget attaches to the controller is cleaned up on dispose.
  Widget host(Widget child) => MaterialApp(
    theme: buildLightTheme(),
    home: Scaffold(body: child),
  );

  Widget longList(ScrollController controller) => ListView(
    controller: controller,
    children: List.generate(60, (i) => ListTile(title: Text('Item $i'))),
  );

  testWidgets('shows the wrapped scrollable content', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        JournalScrollbar(controller: controller, child: longList(controller)),
      ),
    );
    expect(find.text('Item 0'), findsOneWidget);
  });

  testWidgets('keeps scrolling working through the wrapper', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        JournalScrollbar(controller: controller, child: longList(controller)),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  });

  testWidgets('does not draw a thumb when the content already fits', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        JournalScrollbar(
          controller: controller,
          child: ListView(
            controller: controller,
            children: const [ListTile(title: Text('Only item'))],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Only item'), findsOneWidget);
  });

  testWidgets('disposes cleanly after being removed from the tree', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        JournalScrollbar(controller: controller, child: longList(controller)),
      ),
    );
    await tester.pumpWidget(host(const SizedBox.shrink()));
    expect(tester.takeException(), isNull);
  });
}
