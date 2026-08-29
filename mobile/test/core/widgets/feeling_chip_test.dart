// Widget coverage for [FeelingChip] — the one chip every screen in the app
// now draws a feeling with (UX-5). Both variants ([FeelingChipVariant.display]
// and [FeelingChipVariant.selectable]) are exercised in the light and dark
// halves of every shipped palette, and the valence colours themselves are
// checked for the 4.5:1 text contrast `journal_palette.dart` promises —
// there is no golden-image harness in this repo, so this file is the
// visual proof the widget doc points to instead.

import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/theme/journal_metrics.dart';
import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:find_my_patterns/core/widgets/feeling_chips.dart';
import 'package:find_my_patterns/core/widgets/journal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [child] in a themed host, [dark] or light.
Widget _host(Widget child, {required bool dark}) => MaterialApp(
  theme: dark ? buildDarkTheme() : buildLightTheme(),
  home: Scaffold(body: Center(child: child)),
);

/// The [Container] a [FeelingChip] paints its pill with.
///
/// Not the only [Container] in the subtree — [FeelingDot] builds one too —
/// so this picks the one with a [BorderRadius] set: the pill uses
/// [JournalShapes.full], the dot is a plain circle with none.
Container _pillOf(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byType(FeelingChip),
        matching: find.byType(Container),
      ),
    )
    .firstWhere(
      (container) =>
          (container.decoration as BoxDecoration?)?.borderRadius != null,
    );

BoxDecoration _decorationOf(WidgetTester tester) =>
    _pillOf(tester).decoration! as BoxDecoration;

Color _textColorOf(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!.color!;

/// The WCAG contrast ratio between two colours, via [Color.computeLuminance]
/// — the same relative-luminance formula the 4.5:1 body-text rule and the
/// 3:1 outline rule in `journal_palette.dart`'s own doc comment are stated
/// against.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final brighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (brighter + 0.05) / (darker + 0.05);
}

void main() {
  group('FeelingChip — display variant', () {
    for (final dark in [false, true]) {
      final theming = dark ? 'dark' : 'light';

      testWidgets('shows a dot and the label in $theming', (tester) async {
        await tester.pumpWidget(
          _host(
            const FeelingChip(label: 'Grateful', color: Color(0xFF2A7430)),
            dark: dark,
          ),
        );

        expect(find.text('Grateful'), findsOneWidget);
        expect(find.byType(FeelingDot), findsOneWidget);
      });

      testWidgets('paints the border, the dot and the label text in its own '
          'colour in $theming', (tester) async {
        const accent = Color(0xFF2A7430);
        await tester.pumpWidget(
          _host(
            const FeelingChip(label: 'Grateful', color: accent),
            dark: dark,
          ),
        );

        final decoration = _decorationOf(tester);
        expect(decoration.border, Border.all(color: accent, width: 1));
        expect(
          tester.widget<FeelingDot>(find.byType(FeelingDot)).color,
          accent,
        );
        expect(_textColorOf(tester, 'Grateful'), accent);
      });

      testWidgets(
        'is never filled — the good variant is outline-only in $theming',
        (tester) async {
          await tester.pumpWidget(
            _host(
              const FeelingChip(
                label: 'Grateful',
                color: Color(0xFF2A7430),
              ),
              dark: dark,
            ),
          );

          expect(_decorationOf(tester).color, Colors.transparent);
        },
      );

      testWidgets('shows an intensity suffix only when one is given in '
          '$theming', (tester) async {
        await tester.pumpWidget(
          _host(
            const FeelingChip(
              label: 'Stressed',
              color: Color(0xFFB3441A),
              intensityLabel: '3 of 5',
            ),
            dark: dark,
          ),
        );

        expect(find.text('3 of 5'), findsOneWidget);
      });

      testWidgets('shows no suffix when none is given in $theming', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            const FeelingChip(label: 'Stressed', color: Color(0xFFB3441A)),
            dark: dark,
          ),
        );

        expect(find.textContaining(' of '), findsNothing);
      });
    }

    testWidgets('is not tappable — no Semantics tap action is exposed', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const FeelingChip(label: 'Grateful', color: Color(0xFF2A7430)),
          dark: false,
        ),
      );
      expect(
        tester.getSemantics(find.text('Grateful')),
        isNot(matchesSemantics(hasTapAction: true)),
      );
      handle.dispose();
    });
  });

  group('FeelingChip — selectable variant', () {
    for (final dark in [false, true]) {
      final theming = dark ? 'dark' : 'light';

      testWidgets('selected: a tinted fill, a 2px accent border and '
          'accent-coloured bold text in $theming', (tester) async {
        const accent = Color(0xFFB3441A);
        await tester.pumpWidget(
          _host(
            FeelingChip(
              label: 'Stressed',
              color: accent,
              variant: FeelingChipVariant.selectable,
              selected: true,
              onTap: () {},
            ),
            dark: dark,
          ),
        );

        final decoration = _decorationOf(tester);
        expect(decoration.color, accent.withValues(alpha: 0.12));
        expect(decoration.border, Border.all(color: accent, width: 2));
        expect(_textColorOf(tester, 'Stressed'), accent);
        expect(
          tester.widget<Text>(find.text('Stressed')).style!.fontWeight,
          FontWeight.bold,
        );
      });

      testWidgets('unselected: a neutral fill and outline, no accent text '
          'in $theming', (tester) async {
        const accent = Color(0xFFB3441A);
        await tester.pumpWidget(
          _host(
            FeelingChip(
              label: 'Stressed',
              color: accent,
              variant: FeelingChipVariant.selectable,
              onTap: () {},
            ),
            dark: dark,
          ),
        );

        expect(_textColorOf(tester, 'Stressed'), isNot(accent));
        final decoration = _decorationOf(tester);
        expect(decoration.color, isNot(accent.withValues(alpha: 0.12)));
        expect(decoration.border!.top.width, 1);
      });
    }

    testWidgets('suggested appends a "suggested" note', (tester) async {
      await tester.pumpWidget(
        _host(
          FeelingChip(
            label: 'Stressed',
            color: const Color(0xFFB3441A),
            variant: FeelingChipVariant.selectable,
            suggested: true,
            onTap: () {},
          ),
          dark: false,
        ),
      );
      expect(find.text('suggested'), findsOneWidget);
    });

    testWidgets('not suggested shows no note', (tester) async {
      await tester.pumpWidget(
        _host(
          FeelingChip(
            label: 'Stressed',
            color: const Color(0xFFB3441A),
            variant: FeelingChipVariant.selectable,
            onTap: () {},
          ),
          dark: false,
        ),
      );
      expect(find.text('suggested'), findsNothing);
    });

    testWidgets('removable shows a trailing × and announces itself as '
        'removable, not as a checkbox', (tester) async {
      final handle = tester.ensureSemantics();
      var removed = false;
      await tester.pumpWidget(
        _host(
          FeelingChip(
            label: 'Stressed',
            color: const Color(0xFFB3441A),
            variant: FeelingChipVariant.selectable,
            selected: true,
            removable: true,
            onTap: () => removed = true,
          ),
          dark: false,
        ),
      );

      expect(find.text('×'), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel('Stressed'));
      expect(
        node,
        matchesSemantics(label: 'Stressed', isButton: true, hasTapAction: true),
      );
      expect(node.hintOverrides?.onTapHint, 'remove');

      await tester.tap(find.bySemanticsLabel('Stressed'));
      expect(removed, isTrue);
      handle.dispose();
    });

    testWidgets('non-removable announces as a checkbox, not a button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var toggled = false;
      await tester.pumpWidget(
        _host(
          FeelingChip(
            label: 'Stressed',
            color: const Color(0xFFB3441A),
            variant: FeelingChipVariant.selectable,
            onTap: () => toggled = true,
          ),
          dark: false,
        ),
      );

      final node = tester.getSemantics(find.bySemanticsLabel('Stressed'));
      expect(
        node,
        matchesSemantics(
          label: 'Stressed',
          hasCheckedState: true,
          isChecked: false,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );

      await tester.tap(find.bySemanticsLabel('Stressed'));
      expect(toggled, isTrue);
      handle.dispose();
    });

    testWidgets('disabled dims the chip and drops the tap entirely', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var tapped = false;
      await tester.pumpWidget(
        _host(
          FeelingChip(
            label: 'Stressed',
            color: const Color(0xFFB3441A),
            variant: FeelingChipVariant.selectable,
            enabled: false,
            onTap: () => tapped = true,
          ),
          dark: false,
        ),
      );

      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(FeelingChip),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.45);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Stressed')),
        matchesSemantics(
          label: 'Stressed',
          hasCheckedState: true,
          isChecked: false,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );

      await tester.tap(find.bySemanticsLabel('Stressed'), warnIfMissed: false);
      expect(tapped, isFalse);
      handle.dispose();
    });
  });

  group('FeelingChip — valence colour contrast', () {
    // The acceptance criterion is "text contrast >= 4.5:1 on the dark
    // themes" -- but a colour set that only ever meets that bar on dark
    // surfaces would leave the light papers unchecked, so this walks every
    // palette's both halves rather than only the dark ones.
    test('every feeling hue clears 4.5:1 against surface and '
        'surfaceContainer, in every palette, both themes', () {
      for (final palette in JournalPalette.values) {
        for (final dark in [false, true]) {
          final colors = palette.colors(dark: dark);
          final hues = [
            colors.feelings.uplifted,
            colors.feelings.steady,
            colors.feelings.tense,
            colors.feelings.low,
          ];
          for (final hue in hues) {
            for (final surface in [colors.surface, colors.surfaceContainer]) {
              final ratio = _contrastRatio(hue, surface);
              expect(
                ratio,
                greaterThanOrEqualTo(4.5),
                reason:
                    '${palette.id} ${dark ? 'dark' : 'light'}: $hue on '
                    '$surface only clears ${ratio.toStringAsFixed(2)}:1',
              );
            }
          }
        }
      }
    });
  });
}
