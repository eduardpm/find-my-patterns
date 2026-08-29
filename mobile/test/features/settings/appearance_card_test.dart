import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:find_my_patterns/features/settings/appearance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

void main() {
  Widget app() => const MaterialApp(home: Scaffold(body: AppearanceCard()));

  testWidgets('shows both group labels in the accessibility tree', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(Harness().scope(app()));
    await tester.pumpAndSettle();

    // Unlike the shared Eyebrow, these labels are the only name their radio
    // group has, so they must reach a screen reader rather than being
    // silenced the way every other eyebrow in the app is. Both labels merge
    // into the card's one semantics node (there is no boundary around a
    // plain Text), so the proof is that the merged label still carries their
    // words rather than that either produces a node of its own.
    final label = tester.getSemantics(find.text('LIGHT OR DARK')).label;
    expect(label, contains('LIGHT OR DARK'));
    expect(label, contains('PAPER'));
    handle.dispose();
  });

  testWidgets(
    'marks the mode options as a single-choice radio group',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        Harness(
          settings: const AppSettings(themeMode: ThemeModeSetting.light),
        ).scope(app()),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Light')),
        matchesSemantics(
          label: 'Light',
          isButton: true,
          isInMutuallyExclusiveGroup: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Dark')),
        matchesSemantics(
          label: 'Dark',
          isButton: true,
          isInMutuallyExclusiveGroup: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    },
  );

  testWidgets('selecting a mode saves it', (tester) async {
    final harness = Harness();
    await tester.pumpWidget(harness.scope(app()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(harness.store.savedThemeModes.single, ThemeModeSetting.dark);
  });

  testWidgets(
    'marks the palette options as a single-choice radio group',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(Harness().scope(app()));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Warm paper'))),
        matchesSemantics(
          isButton: true,
          isInMutuallyExclusiveGroup: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Sage'))),
        matchesSemantics(
          isButton: true,
          isInMutuallyExclusiveGroup: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    },
  );

  testWidgets('selecting a palette saves it', (tester) async {
    final harness = Harness();
    await tester.pumpWidget(harness.scope(app()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sage'));
    await tester.pumpAndSettle();

    expect(harness.store.savedPalettes.single, JournalPalette.sage);
  });
}
