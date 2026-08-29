import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/core/widgets/pattern_echo_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  const meetingsEcho = PatternEcho(
    'pattern-1',
    'meetings',
    'anxious',
    5,
    4,
    10,
    2.1,
    'You have felt anxious after meetings 4 of the last 10 times.',
  );

  const lateNightEcho = PatternEcho(
    'pattern-2',
    'late nights',
    'exhausted',
    3,
    3,
    8,
    1.8,
    'Late nights have shown up alongside feeling exhausted.',
  );

  group('PatternEchoPanel', () {
    testWidgets('renders nothing when there are no echoes', (tester) async {
      await tester.pumpWidget(
        host(PatternEchoPanel(echoes: const [], onDismiss: () {})),
      );
      expect(find.byType(PatternEchoPanel), findsOneWidget);
      expect(
        find.text('You have written about this before'),
        findsNothing,
      );
    });

    testWidgets('shows the heading and every echo\'s own narrative text', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          PatternEchoPanel(
            echoes: const [meetingsEcho, lateNightEcho],
            onDismiss: () {},
          ),
        ),
      );
      expect(
        find.text('You have written about this before'),
        findsOneWidget,
      );
      expect(find.text(meetingsEcho.narrativeText), findsOneWidget);
      expect(find.text(lateNightEcho.narrativeText), findsOneWidget);
    });

    testWidgets('calls onDismiss when the dismiss button is tapped', (
      tester,
    ) async {
      var dismissed = false;
      await tester.pumpWidget(
        host(
          PatternEchoPanel(
            echoes: const [meetingsEcho],
            onDismiss: () => dismissed = true,
          ),
        ),
      );
      await tester.tap(find.byTooltip('Dismiss'));
      expect(dismissed, isTrue);
    });

    testWidgets('labels the dismiss control for assistive technology', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          PatternEchoPanel(echoes: const [meetingsEcho], onDismiss: () {}),
        ),
      );
      expect(
        tester.getSemantics(find.byTooltip('Dismiss')),
        matchesSemantics(label: 'Dismiss', hasTapAction: true, isButton: true),
      );
      handle.dispose();
    });

    // Regression test for issue #5: the header row's title used to sit in
    // a `mainAxisSize.min` inner `Row`, which gave its `Flexible` text
    // unbounded width and let it push the dismiss button off the card —
    // Flutter's "RIGHT OVERFLOWED BY 20 PIXELS" stripes at 1080x2400. A
    // narrow width plus a large text scale is what used to trigger it.
    for (final textScale in [1.0, 1.3, 2.0]) {
      testWidgets(
        'has no overflow at 320dp width and ${textScale}x text scale',
        (tester) async {
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 800),
                textScaler: TextScaler.linear(textScale),
              ),
              child: host(
                PatternEchoPanel(
                  echoes: const [meetingsEcho, lateNightEcho],
                  onDismiss: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          // The title wraps rather than being clipped, and the dismiss
          // control stays fully readable/tappable — findsOneWidget (rather
          // than findsNothing) confirms neither was replaced by an
          // overflow-error render object.
          expect(
            find.text('You have written about this before'),
            findsOneWidget,
          );
          expect(find.byTooltip('Dismiss'), findsOneWidget);
        },
      );
    }

    testWidgets(
      'keeps the dismiss control at the touch-target floor at 320dp and 2x scale',
      (tester) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: host(
              PatternEchoPanel(echoes: const [meetingsEcho], onDismiss: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dismissSize = tester.getSize(find.byTooltip('Dismiss'));
        expect(dismissSize.width, greaterThanOrEqualTo(44));
        expect(dismissSize.height, greaterThanOrEqualTo(44));
      },
    );
  });
}
