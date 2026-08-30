import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/features/premium/upgrade_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'names what Premium unlocks and says purchasing is not wired up yet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: const UpgradeScreen(),
        ),
      );

      expect(find.text('Upgrade'), findsOneWidget); // the AppBar title.
      expect(find.text('Premium'), findsOneWidget);
      expect(
        find.textContaining('N-of-1 experiments'),
        findsOneWidget,
      );
      // M-3, #48's out-of-scope line: Play Billing is a later, store-launch
      // ticket -- this screen says so rather than pretending to purchase.
      expect(
        find.textContaining('Purchasing is not available'),
        findsOneWidget,
      );
    },
  );
}
