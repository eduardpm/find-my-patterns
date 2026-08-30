import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The screen widths every screen is checked at: the narrowest phone this app
/// treats as real, and one common step up.
///
/// See `ACCESSIBILITY.md` §3 for why 320dp is the floor.
const List<double> kMatrixWidths = [320, 360];

/// The text scales every screen is checked at.
///
/// **1.0 is not optional.** `IntensityDials`' 32px overflow (#150) and
/// `_WorthTryingSection`'s 34px one (#155) both reproduced at the default
/// scale, before any dynamic-type scaling was applied at all — a
/// scale-only sweep would have missed both.
const List<double> kMatrixScales = [1.0, 1.3, 2.0];

/// A tall viewport, so a screen's own vertical scrolling never truncates what
/// this is trying to measure. Only the *horizontal* axis is asserted on; see
/// [horizontalOverflows].
const double kMatrixHeight = 3000;

/// One reported violation: which invariant broke, and on what text.
class LayoutViolation {
  /// Creates a violation of [kind] concerning [text], described by [detail].
  const LayoutViolation({
    required this.kind,
    required this.text,
    required this.detail,
  });

  /// A short slug for the invariant that broke.
  final String kind;

  /// The rendered text the violation is about, trimmed for readability.
  final String text;

  /// A human-readable statement of the measurement that failed.
  final String detail;

  @override
  String toString() => '[$kind] "$text" — $detail';
}

/// Every laid-out [RenderParagraph] in the current frame, each exactly once.
///
/// `WidgetTester.allRenderObjects` can yield the same object more than once,
/// which would otherwise report one defect several times over and make the
/// failure output lie about how many there are.
Iterable<RenderParagraph> renderedParagraphs(WidgetTester tester) sync* {
  final seen = <RenderObject>{};
  for (final object in tester.allRenderObjects) {
    if (object is! RenderParagraph) continue;
    if (!seen.add(object)) continue;
    if (!object.attached || object.debugNeedsLayout || !object.hasSize) {
      continue;
    }
    yield object;
  }
}

/// Every piece of text this app can render that paints outside the viewport's
/// horizontal bounds.
///
/// **This is an invariant, not a layout assertion.** `CONSTITUTION.md`
/// Article 3 rules out asserting pixel positions, and rightly so — a test
/// that pins a label to x=16 breaks on every visual tweak and proves
/// nothing. This asserts something categorically different and much weaker:
/// that text renders *somewhere inside the screen*. No visual tweak can
/// legitimately break it, and nothing but a real defect does. It is the
/// generalisation of `ACCESSIBILITY.md` §3's per-screen geometry checks,
/// which that document already requires.
///
/// It exists because the classic `RenderFlex` overflow — the one that throws,
/// and that `expect(tester.takeException(), isNull)` catches — is only one of
/// the shapes this codebase keeps producing. #164's extended
/// `FloatingActionButton` rendered off *both* screen edges without throwing
/// at all, because `FloatingActionButton.extended` locks its height and
/// leaves its width unconstrained. Nothing in the widget tree was wrong; the
/// pixels were. Only a bounds check sees that.
///
/// A small [tolerance] absorbs sub-pixel rounding from text shaping at
/// fractional scales; it is far below the size of any real defect (the
/// smallest this project has filed is 27px).
List<LayoutViolation> horizontalOverflows(
  WidgetTester tester, {
  required double width,
  double tolerance = 1.0,
}) {
  final violations = <LayoutViolation>[];
  for (final object in renderedParagraphs(tester)) {
    final Offset origin;
    try {
      origin = object.localToGlobal(Offset.zero);
    } on Object {
      // Detached or otherwise unlocatable in this frame; nothing to assert.
      continue;
    }
    final rect = origin & object.size;
    final text = object.text.toPlainText().trim();
    if (text.isEmpty) continue;
    if (rect.left < -tolerance) {
      violations.add(
        LayoutViolation(
          kind: 'off-screen-left',
          text: _clip(text),
          detail:
              'left edge at ${rect.left.toStringAsFixed(1)}px, '
              '${(-rect.left).toStringAsFixed(1)}px past the screen',
        ),
      );
    }
    if (rect.right > width + tolerance) {
      violations.add(
        LayoutViolation(
          kind: 'off-screen-right',
          text: _clip(text),
          detail:
              'right edge at ${rect.right.toStringAsFixed(1)}px, '
              '${(rect.right - width).toStringAsFixed(1)}px past the '
              '${width.toStringAsFixed(0)}px screen',
        ),
      );
    }
  }
  return violations;
}

/// Every single-word label this app breaks across lines while the screen
/// still had room for it.
///
/// The third shape in the family, and the one no exception and no bounds
/// check sees. #168's day view renders "Relaxed" as "Relaxe" / "d" inside a
/// chip that was squeezed into the right-hand half of a row: nothing throws,
/// nothing leaves the screen, and the label is still technically legible —
/// it just reads as broken. The mechanism is always the same, a fixed-width
/// sibling starving an `Expanded`/`Wrap` next to it.
///
/// Deliberately narrow, to stay free of false positives:
///
/// - only text with **no whitespace at all** counts, so a sentence wrapping
///   normally — which is exactly what `ACCESSIBILITY.md` §3 asks for — is
///   never flagged;
/// - and only when the paragraph was laid out into less than
///   [starvedFraction] of the screen's width, so a genuinely enormous word
///   that could not fit any layout is not blamed on the layout.
List<LayoutViolation> brokenWords(
  WidgetTester tester, {
  required double width,
  double starvedFraction = 0.6,
}) {
  final violations = <LayoutViolation>[];
  for (final object in renderedParagraphs(tester)) {
    final text = object.text.toPlainText().trim();
    if (text.isEmpty) continue;
    // A single word: no spaces, tabs or newlines anywhere in it.
    if (text.contains(RegExp(r'\s'))) continue;
    // How wide this word wants to be on one line. `RenderParagraph` exposes
    // no line metrics, but a single word's unwrapped width is exactly its
    // max intrinsic width -- and comparing that against the width it was
    // actually given says both *that* it broke and *by how much it was
    // starved*, which a line count would not.
    final double wanted;
    try {
      wanted = object.getMaxIntrinsicWidth(double.infinity);
    } on Object {
      continue;
    }
    if (wanted <= object.size.width + 1) continue;
    if (object.size.width >= width * starvedFraction) continue;
    violations.add(
      LayoutViolation(
        kind: 'word-broken-across-lines',
        text: _clip(text),
        detail:
            'needs ${wanted.toStringAsFixed(1)}px on one line but was given '
            '${object.size.width.toStringAsFixed(1)}px of a '
            '${width.toStringAsFixed(0)}px screen',
      ),
    );
  }
  return violations;
}

String _clip(String text) =>
    text.length <= 40 ? text : '${text.substring(0, 40)}…';

/// Pumps [child] at one cell of the matrix and lets it settle.
///
/// Uses `.copyWith` on the **ambient** [MediaQueryData] rather than building a
/// fresh one: a bare `MediaQueryData(textScaler: ...)` discards every other
/// field, including `size` and `padding`, which is exactly how #150's
/// status-bar defect was first missed. See `ACCESSIBILITY.md` §3.
///
/// Falls back to a fixed number of pumps when the screen never settles — a
/// permanent `CircularProgressIndicator` animates forever, and a loading state
/// is still a state worth measuring.
Future<void> pumpMatrixCell(
  WidgetTester tester,
  Widget child, {
  required double width,
  required double scale,
}) async {
  tester.view.physicalSize = Size(width, kMatrixHeight);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child,
      ),
    ),
  );
  try {
    await tester.pumpAndSettle();
  } on Object {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

/// Asserts all three layout invariants for the frame currently pumped.
///
/// The three shapes this codebase keeps producing, in one place:
///
/// 1. a thrown `RenderFlex` overflow — the classic, and the only one the
///    existing per-screen tests catch;
/// 2. text painted outside the screen — silent, see [horizontalOverflows];
/// 3. a single word broken across lines — silent, see [brokenWords].
void expectNoLayoutViolations(WidgetTester tester, {required double width}) {
  final thrown = tester.takeException();
  final violations = [
    ...horizontalOverflows(tester, width: width),
    ...brokenWords(tester, width: width),
  ];
  if (thrown == null && violations.isEmpty) return;
  final report = StringBuffer();
  if (thrown != null) report.writeln('  [threw] $thrown');
  for (final violation in violations) {
    report.writeln('  $violation');
  }
  fail('Layout violations at ${width.toStringAsFixed(0)}dp:\n$report');
}
