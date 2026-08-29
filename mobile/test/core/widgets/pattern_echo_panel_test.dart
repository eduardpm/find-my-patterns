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
  });
}
