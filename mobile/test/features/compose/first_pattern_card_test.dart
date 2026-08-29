import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/features/compose/first_pattern_card.dart';
import 'package:find_my_patterns/features/compose/first_pattern_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'json_fixtures.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  final pattern = patternFromJson(
    patternJson(occurrenceCount: 3),
    FeelingCatalog.empty,
  );

  group('FirstPatternCard', () {
    testWidgets('shows the ticket\'s exact copy, naming no number', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(FirstPatternCard(pattern: pattern, onTap: () {})),
      );

      expect(find.text(firstPatternCardText), findsOneWidget);
      expect(find.textContaining('3'), findsNothing);
    });

    testWidgets('tapping the card calls onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        host(FirstPatternCard(pattern: pattern, onTap: () => tapped = true)),
      );

      await tester.tap(find.byType(FirstPatternCard));

      expect(tapped, isTrue);
    });
  });
}
