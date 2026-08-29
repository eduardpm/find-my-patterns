import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/widgets/journal_page_wash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Article 3: the gradient itself is a visual detail verified by looking at
  // the app (Article 5). What is worth proving here is that the wash is
  // decorative — it must never surface to a screen reader — and that it
  // renders under the ambient theme without throwing.
  Widget host(Widget child) => MaterialApp(
    theme: buildLightTheme(),
    home: Scaffold(body: child),
  );

  testWidgets('renders without throwing', (tester) async {
    await tester.pumpWidget(host(const JournalPageWash()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('excludes itself from the accessibility tree', (tester) async {
    await tester.pumpWidget(host(const JournalPageWash()));
    expect(
      find.descendant(
        of: find.byType(JournalPageWash),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });
}
