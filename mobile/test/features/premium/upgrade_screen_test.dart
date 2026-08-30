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

  group('dynamic type at the required matrix (#155)', () {
    // `upgrade_screen.dart:25`'s `Stack` -- flagged as "likely clean" by
    // the orchestrator, but a negative result stated with a number is
    // still a real deliverable here. Every cell is measured, not assumed.
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          'renders with no overflow at ${width.toInt()}dp / ${scale}x',
          (tester) async {
            tester.view.physicalSize = Size(width, 3000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: MaterialApp(
                    theme: buildLightTheme(),
                    home: const UpgradeScreen(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.text('Premium'), findsOneWidget);
            expect(
              find.textContaining('N-of-1 experiments'),
              findsOneWidget,
            );
            expect(
              find.textContaining('Purchasing is not available'),
              findsOneWidget,
            );
          },
        );
      }
    }
  });
}
