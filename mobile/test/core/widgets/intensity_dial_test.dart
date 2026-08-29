import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/widgets/intensity_dial.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  const grateful = Feeling(
    'grateful',
    'Grateful',
    Valence.positive,
    'uplifted',
  );
  const anxious = Feeling('anxious', 'Anxious', Valence.negative, 'tense');

  group('IntensityDials', () {
    testWidgets('renders nothing when there are no feelings', (tester) async {
      await tester.pumpWidget(
        host(
          IntensityDials(
            feelings: const [],
            intensities: const {},
            onChange: (_, _) {},
            min: 1,
            max: 5,
          ),
        ),
      );
      expect(find.byType(IntensityDials), findsOneWidget);
      expect(find.text('How strongly?'), findsNothing);
    });

    testWidgets('asks "How strongly?" for a single feeling', (tester) async {
      await tester.pumpWidget(
        host(
          IntensityDials(
            feelings: const [grateful],
            intensities: const {},
            onChange: (_, _) {},
            min: 1,
            max: 5,
          ),
        ),
      );
      expect(find.text('How strongly?'), findsOneWidget);
    });

    testWidgets('asks the plural question for several feelings', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          IntensityDials(
            feelings: const [grateful, anxious],
            intensities: const {},
            onChange: (_, _) {},
            min: 1,
            max: 5,
          ),
        ),
      );
      expect(
        find.text('How strongly did you feel each?'),
        findsOneWidget,
      );
    });

    testWidgets('says it is optional, in words rather than by omission', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          IntensityDials(
            feelings: const [grateful],
            intensities: const {},
            onChange: (_, _) {},
            min: 1,
            max: 5,
          ),
        ),
      );
      expect(find.bySemanticsLabel('Optional'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('renders one row of stops per feeling, from min to max', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          IntensityDials(
            feelings: const [grateful, anxious],
            intensities: const {},
            onChange: (_, _) {},
            min: 1,
            max: 5,
          ),
        ),
      );
      for (final stop in [1, 2, 3, 4, 5]) {
        expect(
          find.bySemanticsLabel('Grateful, $stop of 5'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Anxious, $stop of 5'),
          findsOneWidget,
        );
      }
      handle.dispose();
    });

    testWidgets('uses the min/max the caller passes rather than a fixed '
        'five-point scale', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          IntensityDials(
            feelings: const [grateful],
            intensities: const {},
            onChange: (_, _) {},
            min: 1,
            max: 3,
          ),
        ),
      );
      expect(find.bySemanticsLabel('Grateful, 1 of 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Grateful, 3 of 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Grateful, 4 of 3'), findsNothing);
      handle.dispose();
    });

    testWidgets('tapping a stop reports it for the right feeling', (
      tester,
    ) async {
      final calls = <(Feeling, int?)>[];
      await tester.pumpWidget(
        host(
          IntensityDials(
            feelings: const [grateful, anxious],
            intensities: const {},
            onChange: (feeling, value) => calls.add((feeling, value)),
            min: 1,
            max: 5,
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Anxious, 3 of 5'));
      expect(calls, [(anxious, 3)]);
    });

    testWidgets('tapping the current value clears it', (tester) async {
      final calls = <(Feeling, int?)>[];
      await tester.pumpWidget(
        host(
          IntensityDials(
            feelings: const [grateful],
            intensities: const {'grateful': 3},
            onChange: (feeling, value) => calls.add((feeling, value)),
            min: 1,
            max: 5,
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Grateful, 3 of 5'));
      expect(calls, [(grateful, null)]);
    });

    testWidgets('a Clear button appears once a feeling has a value, and '
        'clears it', (tester) async {
      final calls = <(Feeling, int?)>[];
      await tester.pumpWidget(
        host(
          IntensityDials(
            feelings: const [grateful],
            intensities: const {},
            onChange: (feeling, value) => calls.add((feeling, value)),
            min: 1,
            max: 5,
          ),
        ),
      );
      expect(find.text('Clear'), findsNothing);

      await tester.pumpWidget(
        host(
          IntensityDials(
            feelings: const [grateful],
            intensities: const {'grateful': 2},
            onChange: (feeling, value) => calls.add((feeling, value)),
            min: 1,
            max: 5,
          ),
        ),
      );
      expect(find.text('Clear'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      expect(calls, [(grateful, null)]);
    });

    testWidgets('shows the never-required footer', (tester) async {
      await tester.pumpWidget(
        host(
          IntensityDials(
            feelings: const [grateful],
            intensities: const {},
            onChange: (_, _) {},
            min: 1,
            max: 5,
          ),
        ),
      );
      expect(
        find.text(
          'Skip any of these and nothing changes — patterns never '
          'depend on them.',
        ),
        findsOneWidget,
      );
    });
  });
}
