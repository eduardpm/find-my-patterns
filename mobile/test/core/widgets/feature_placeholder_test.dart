import 'package:find_my_patterns/core/widgets/feature_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows the title, message and icon', (tester) async {
    await tester.pumpWidget(
      host(
        const PlaceholderView(
          icon: Icons.home,
          title: 'Home',
          message: 'Replace this screen.',
        ),
      ),
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Replace this screen.'), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
  });

  testWidgets('omits the icon when none is given', (tester) async {
    await tester.pumpWidget(
      host(const PlaceholderView(title: 'Home', message: 'x')),
    );
    expect(find.byType(Icon), findsNothing);
  });
}
