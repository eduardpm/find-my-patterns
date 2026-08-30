import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dynamic_type_matrix.dart';

/// Tests for the shared dynamic-type harness itself.
///
/// A harness that silently detects nothing would make every screen it checks
/// look clean, which is the exact failure this project keeps meeting from the
/// other direction (`ACCESSIBILITY.md` §3: "what a green test must actually
/// prove"). So each invariant is proved to fire on a shape that violates it
/// **and** proved not to fire on the legitimate shape nearest to it.
void main() {
  Widget page(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('horizontalOverflows', () {
    testWidgets('catches text painted past the right edge without throwing', (
      tester,
    ) async {
      // A `Stack` with a positioned child overflows silently: no `RenderFlex`
      // is involved, so nothing throws -- the shape #164's extended FAB had.
      await pumpMatrixCell(
        tester,
        page(
          Stack(
            children: [
              Positioned(
                left: 300,
                top: 0,
                child: const Text(
                  'past the edge',
                  textDirection: TextDirection.ltr,
                ),
              ),
            ],
          ),
        ),
        width: 320,
        scale: 1,
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'this shape must not throw, or the test proves nothing',
      );
      final violations = horizontalOverflows(tester, width: 320);
      expect(violations, hasLength(1));
      expect(violations.single.kind, 'off-screen-right');
      expect(violations.single.text, 'past the edge');
    });

    testWidgets('catches text painted past the left edge', (tester) async {
      await pumpMatrixCell(
        tester,
        page(
          Stack(
            children: [
              Positioned(
                left: -80,
                top: 0,
                child: const Text('before the edge'),
              ),
            ],
          ),
        ),
        width: 320,
        scale: 1,
      );

      final violations = horizontalOverflows(tester, width: 320);
      expect(violations.single.kind, 'off-screen-left');
    });

    testWidgets('does not flag text that fits', (tester) async {
      await pumpMatrixCell(
        tester,
        page(const Center(child: Text('fits'))),
        width: 320,
        scale: 1,
      );

      expect(horizontalOverflows(tester, width: 320), isEmpty);
    });

    testWidgets('does not flag a long sentence wrapping normally', (
      tester,
    ) async {
      // Wrapping a sentence is what `ACCESSIBILITY.md` §3 asks layouts to do.
      // Flagging it would make the harness useless.
      await pumpMatrixCell(
        tester,
        page(
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Adding a day or two helps your patterns appear sooner, which '
              'is a whole sentence that must wrap across several lines.',
            ),
          ),
        ),
        width: 320,
        scale: 2,
      );

      expect(horizontalOverflows(tester, width: 320), isEmpty);
    });
  });

  group('brokenWords', () {
    testWidgets('catches a single word split across lines in a starved box', (
      tester,
    ) async {
      // #168's shape: a chip squeezed into a fraction of the row, with a
      // one-word label that has to break mid-word to fit it.
      await pumpMatrixCell(
        tester,
        page(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 60,
              child: const Text('Relaxed'),
            ),
          ),
        ),
        width: 320,
        scale: 2,
      );

      final violations = brokenWords(tester, width: 320);
      expect(violations, hasLength(1));
      expect(violations.single.kind, 'word-broken-across-lines');
      expect(violations.single.text, 'Relaxed');
    });

    testWidgets('does not flag a multi-word label wrapping in a narrow box', (
      tester,
    ) async {
      await pumpMatrixCell(
        tester,
        page(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 60,
              child: const Text('Write about yesterday'),
            ),
          ),
        ),
        width: 320,
        scale: 1,
      );

      expect(brokenWords(tester, width: 320), isEmpty);
    });

    testWidgets(
      'does not blame the layout for a word wider than the whole screen',
      (tester) async {
        // Given the full screen and still not fitting, the word -- not the
        // layout -- is the problem, and no `Flexible` or `Wrap` would help.
        await pumpMatrixCell(
          tester,
          page(const Text('Pneumonoultramicroscopicsilicovolcanoconiosis')),
          width: 320,
          scale: 2,
        );

        expect(brokenWords(tester, width: 320), isEmpty);
      },
    );
  });

  group('expectNoLayoutViolations', () {
    testWidgets('passes on a clean screen', (tester) async {
      await pumpMatrixCell(
        tester,
        page(const Center(child: Text('clean'))),
        width: 320,
        scale: 2,
      );

      expectNoLayoutViolations(tester, width: 320);
    });

    testWidgets('reports a thrown RenderFlex overflow', (tester) async {
      await pumpMatrixCell(
        tester,
        page(
          Row(
            children: [
              const SizedBox(width: 400, child: Text('rigid')),
              const SizedBox(width: 400, child: Text('sibling')),
            ],
          ),
        ),
        width: 320,
        scale: 1,
      );

      expect(
        () => expectNoLayoutViolations(tester, width: 320),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}
