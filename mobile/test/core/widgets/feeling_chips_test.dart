import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/widgets/feeling_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const happy = Feeling('happy', 'Happy', Valence.positive, 'uplifted');
const excited = Feeling('excited', 'Excited', Valence.positive, 'uplifted');
const grateful = Feeling('grateful', 'Grateful', Valence.positive, 'uplifted');
const calm = Feeling('calm', 'Calm', Valence.neutral, 'steady');
const overwhelmed = Feeling(
  'overwhelmed',
  'Overwhelmed',
  Valence.negative,
  'tense',
);
const frustrated = Feeling(
  'frustrated',
  'Frustrated',
  Valence.negative,
  'tense',
);
const sad = Feeling('sad', 'Sad', Valence.negative, 'low');

const uplifted = FeelingGroup('uplifted', 'Uplifted', Valence.positive, [
  happy,
  excited,
  grateful,
]);
const steady = FeelingGroup('steady', 'Steady', Valence.neutral, [calm]);
const tense = FeelingGroup('tense', 'Tense', Valence.negative, [
  overwhelmed,
  frustrated,
]);
const low = FeelingGroup('low', 'Low', Valence.negative, [sad]);

const allGroups = [uplifted, steady, tense, low];

// A second, long-label vocabulary reserved for the #111 textScale-2.0
// overflow check below: real words from the backend's own vocabulary
// (`specs/research/unified-backlog.md`'s catalogue) chosen because they are
// long enough that halving each chip's line share -- the direct consequence
// of chips finally sitting side by side -- is exactly the new condition
// that could overflow a `Row` that never had to share space before.
const affectionate = Feeling(
  'affectionate',
  'Affectionate',
  Valence.positive,
  'uplifted',
);
const disappointed = Feeling(
  'disappointed',
  'Disappointed',
  Valence.negative,
  'low',
);
const longLabelUplifted = FeelingGroup(
  'uplifted',
  'Uplifted',
  Valence.positive,
  [affectionate, happy],
);
const longLabelTense = FeelingGroup('tense', 'Tense', Valence.negative, [
  overwhelmed,
  frustrated,
]);
const longLabelLow = FeelingGroup('low', 'Low', Valence.negative, [
  disappointed,
  sad,
]);
const longLabelGroups = [longLabelUplifted, longLabelTense, longLabelLow];

/// A controlled-component test harness: owns `selected` the way a real
/// screen would, feeding it back into [FeelingChips] on every
/// [FeelingChips.onSelectionChange] call, and exposes every callback
/// invocation to the test through [onChangeSpy].
class _Harness extends StatefulWidget {
  const _Harness({
    this.groups = allGroups,
    this.initial = const [],
    this.max = kMaxFeelingsPerEntry,
    this.suggestedKeys = const {},
    this.onChangeSpy,
  });

  final List<FeelingGroup> groups;
  final List<Feeling> initial;
  final int max;
  final Set<String> suggestedKeys;
  final ValueChanged<List<Feeling>>? onChangeSpy;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late List<Feeling> selected = widget.initial;

  /// Lets a test change [selected] the way an unrelated part of a real
  /// screen might — never through [FeelingChips.onSelectionChange] — to
  /// prove the widget picks up an externally-driven `selected` while a
  /// sheet is open.
  void setExternally(List<Feeling> next) => setState(() => selected = next);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: FeelingChips(
        groups: widget.groups,
        selected: selected,
        max: widget.max,
        suggestedKeys: widget.suggestedKeys,
        onSelectionChange: (next) {
          widget.onChangeSpy?.call(next);
          setState(() => selected = next);
        },
      ),
    ),
  );
}

void main() {
  group('FeelingChips — empty-selection state', () {
    testWidgets('shows the empty-state line when nothing is chosen', (
      tester,
    ) async {
      await tester.pumpWidget(const _Harness());
      expect(
        find.text(
          'Nothing chosen yet — pick a group to see the feelings inside it.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('hides the empty-state line once something is chosen', (
      tester,
    ) async {
      await tester.pumpWidget(_Harness(initial: const [happy]));
      expect(
        find.text(
          'Nothing chosen yet — pick a group to see the feelings inside it.',
        ),
        findsNothing,
      );
    });

    testWidgets('shows no group chips while the catalog has not loaded '
        'yet', (tester) async {
      await tester.pumpWidget(const _Harness(groups: []));
      expect(find.text('Uplifted'), findsNothing);
      expect(
        find.text(
          'Nothing chosen yet — pick a group to see the feelings inside it.',
        ),
        findsOneWidget,
      );
    });
  });

  group('FeelingChips — opening a group and choosing a feeling', () {
    testWidgets('tapping a group opens a sheet with its own feelings', (
      tester,
    ) async {
      await tester.pumpWidget(const _Harness());
      await tester.tap(find.text('Uplifted'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose up to 4. Tap one again to remove it.'),
        findsOneWidget,
      );
      expect(find.text('Happy'), findsOneWidget);
      expect(find.text('Excited'), findsOneWidget);
      expect(find.text('Grateful'), findsOneWidget);
    });

    testWidgets('tapping an unchosen feeling in the sheet adds it', (
      tester,
    ) async {
      List<Feeling>? result;
      await tester.pumpWidget(_Harness(onChangeSpy: (next) => result = next));
      await tester.tap(find.text('Uplifted'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Happy'));
      expect(result, [happy]);
    });

    testWidgets('the Done button closes the sheet', (tester) async {
      await tester.pumpWidget(const _Harness());
      await tester.tap(find.text('Uplifted'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose up to 4. Tap one again to remove it.'),
        findsNothing,
      );
    });
  });

  group('FeelingChips — removing a feeling', () {
    testWidgets('tapping a chosen feeling in the main row removes it', (
      tester,
    ) async {
      List<Feeling>? result;
      await tester.pumpWidget(
        _Harness(initial: const [happy], onChangeSpy: (next) => result = next),
      );
      await tester.tap(find.text('Happy'));
      expect(result, isEmpty);
    });

    testWidgets('tapping a chosen feeling inside its sheet removes it', (
      tester,
    ) async {
      List<Feeling>? result;
      await tester.pumpWidget(
        _Harness(initial: const [happy], onChangeSpy: (next) => result = next),
      );
      await tester.tap(find.text('Uplifted'));
      await tester.pumpAndSettle();
      // "Happy" now appears twice: once in the chosen row behind the sheet,
      // once as the sheet's own checkbox. The checkbox is the last one
      // painted.
      await tester.tap(find.text('Happy').last);
      expect(result, isEmpty);
    });
  });

  group('FeelingChips — the stale-closure regression', () {
    testWidgets(
      'two different feelings tapped inside one open sheet both survive '
      'in the selection',
      (tester) async {
        List<Feeling>? result;
        await tester.pumpWidget(
          _Harness(onChangeSpy: (next) => result = next),
        );
        await tester.tap(find.text('Uplifted'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Happy'));
        await tester.pump();
        expect(result?.map((f) => f.key), ['happy']);

        await tester.tap(find.text('Excited'));
        await tester.pump();

        expect(
          result?.map((f) => f.key).toSet(),
          {'happy', 'excited'},
          reason:
              'A stale closure over the selection as it stood when the '
              'sheet opened would compute oldSelection + excited and drop '
              'happy instead of keeping both.',
        );
      },
    );

    testWidgets(
      'a selection made outside the sheet while it is open is reflected '
      'inside it',
      (tester) async {
        await tester.pumpWidget(const _Harness());
        await tester.tap(find.text('Uplifted'));
        await tester.pumpAndSettle();

        final state = tester.state<_HarnessState>(find.byType(_Harness));
        state.setExternally(const [happy]);
        // One frame runs `didUpdateWidget`, which defers the notifier
        // update to a post-frame callback (see the doc comment on
        // `didUpdateWidget`); a second frame lets the sheet's
        // `ValueListenableBuilder` rebuild from it.
        await tester.pump();
        await tester.pump();

        final handle = tester.ensureSemantics();
        // "Happy" now appears twice: once in the chosen row behind the
        // sheet, once as the sheet's own checkbox.
        expect(
          tester.getSemantics(find.bySemanticsLabel('Happy').last),
          matchesSemantics(
            hasCheckedState: true,
            isChecked: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );
        handle.dispose();
      },
    );
  });

  group('FeelingChips — cross-group selection', () {
    testWidgets(
      'Overwhelmed (Tense) joins Grateful (Uplifted) in the same open '
      'sheet, in 4 taps total with no close/reopen between them — the '
      "issue's Stressed + Grateful case, and the stale-closure regression "
      'now that a single sheet carries every group',
      (tester) async {
        // A tall viewport rather than manual scrolling: the sheet holds
        // all four groups now, and this proves the taps themselves — not
        // where a thumb happens to have scrolled to — satisfy the ≤4-taps
        // acceptance criterion. See `app_test.dart` for the same pattern.
        tester.view.physicalSize = const Size(1000, 3000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        List<Feeling>? result;
        await tester.pumpWidget(
          _Harness(onChangeSpy: (next) => result = next),
        );

        // Tap 1: open the shared sheet, from the Uplifted group chip.
        await tester.tap(find.text('Uplifted'));
        await tester.pumpAndSettle();

        // Tap 2: choose Grateful, in the Uplifted section the sheet
        // opened on.
        await tester.tap(find.text('Grateful'));
        await tester.pump();
        expect(result?.map((f) => f.key), ['grateful']);
        // The sheet is still open: nothing closed to switch groups.
        expect(
          find.text('Choose up to 4. Tap one again to remove it.'),
          findsOneWidget,
        );

        // Tap 3: choose Overwhelmed, from the Tense section of the very
        // same still-open sheet. A stale closure over the selection as it
        // stood when the sheet opened would compute oldSelection +
        // overwhelmed and drop grateful; both must survive.
        await tester.tap(find.text('Overwhelmed'));
        await tester.pump();
        expect(
          result?.map((f) => f.key).toSet(),
          {'grateful', 'overwhelmed'},
        );
        expect(
          find.text('Choose up to 4. Tap one again to remove it.'),
          findsOneWidget,
          reason: 'still open — no close/reopen happened between groups',
        );

        // Tap 4: Done.
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(
          find.text('Choose up to 4. Tap one again to remove it.'),
          findsNothing,
        );
        expect(result?.map((f) => f.key).toSet(), {'grateful', 'overwhelmed'});
      },
    );
  });

  group('FeelingChips — the limit', () {
    testWidgets('shows the limit note once selected reaches max', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Harness(
          initial: const [happy, excited, grateful, calm],
          max: 4,
        ),
      );
      expect(
        find.text(
          "That's as many as one entry can carry. Remove one to choose "
          'another.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('does not show the limit note below max', (tester) async {
      await tester.pumpWidget(_Harness(initial: const [happy], max: 4));
      expect(
        find.text(
          "That's as many as one entry can carry. Remove one to choose "
          'another.',
        ),
        findsNothing,
      );
    });

    testWidgets('does not hide the groups at the limit', (tester) async {
      await tester.pumpWidget(
        _Harness(
          initial: const [happy, excited, grateful, calm],
          max: 4,
        ),
      );
      expect(find.text('Tense'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
    });

    testWidgets('an unchosen feeling in the sheet goes non-interactive at '
        'the limit', (tester) async {
      List<Feeling>? result;
      await tester.pumpWidget(
        _Harness(
          initial: const [happy, excited, grateful, calm],
          max: 4,
          onChangeSpy: (next) => result = next,
        ),
      );
      await tester.tap(find.text('Tense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overwhelmed'));
      expect(result, isNull);

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Overwhelmed')),
        matchesSemantics(
          hasCheckedState: true,
          isChecked: false,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('a chosen feeling in the sheet can still be removed at the '
        'limit', (tester) async {
      List<Feeling>? result;
      await tester.pumpWidget(
        _Harness(
          initial: const [happy, excited, grateful, calm],
          max: 4,
          onChangeSpy: (next) => result = next,
        ),
      );
      await tester.tap(find.text('Steady'));
      await tester.pumpAndSettle();
      // "Calm" now appears twice: once in the chosen row behind the sheet,
      // once as the sheet's own checkbox.
      await tester.tap(find.text('Calm').last);
      expect(result?.map((f) => f.key), ['happy', 'excited', 'grateful']);
    });
  });

  group('FeelingChips — accessibility', () {
    testWidgets('a chosen feeling chip announces itself as removable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_Harness(initial: const [happy]));
      final node = tester.getSemantics(find.bySemanticsLabel('Happy'));
      expect(
        node,
        matchesSemantics(label: 'Happy', isButton: true, hasTapAction: true),
      );
      // The chip's job is removal, so that is the tap action's hint rather
      // than a rewritten name — "Happy, button, double tap to remove"
      // without losing the word the chip is about.
      expect(node.hintOverrides?.onTapHint, 'remove');
      handle.dispose();
    });

    testWidgets('a group chip announces its own word with the count as a '
        'state', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_Harness(initial: const [happy, excited]));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Uplifted')),
        matchesSemantics(
          label: 'Uplifted',
          value: '2 chosen',
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a group chip with nothing chosen carries no count state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const _Harness());
      expect(
        tester.getSemantics(find.bySemanticsLabel('Steady')),
        matchesSemantics(label: 'Steady', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('sheet chips announce as checkboxes, not as a single '
        'exclusive choice', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_Harness(initial: const [happy]));
      await tester.tap(find.text('Uplifted'));
      await tester.pumpAndSettle();

      // "Happy" now appears twice: once in the chosen row behind the
      // sheet, once as the sheet's own checkbox.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Happy').last),
        matchesSemantics(
          hasCheckedState: true,
          isChecked: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Excited')),
        matchesSemantics(
          hasCheckedState: true,
          isChecked: false,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      handle.dispose();
    });
  });

  group('FeelingChips — suggested feelings', () {
    testWidgets('marks a suggested feeling in the chosen row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Harness(initial: const [happy], suggestedKeys: const {'happy'}),
      );
      expect(find.text('suggested'), findsOneWidget);
    });

    testWidgets('marks a suggested feeling inside its sheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Harness(suggestedKeys: const {'excited'}),
      );
      await tester.tap(find.text('Uplifted'));
      await tester.pumpAndSettle();
      expect(find.text('suggested'), findsOneWidget);
    });
  });

  group(
    'FeelingChips — chip layout wraps at 360dp, not one per row (#111)',
    () {
      // #111: `FeelingChip`'s pill used to expand to the full line width
      // (`Container(alignment: Alignment.center)`), so every chip here landed
      // on a row of its own -- exactly the "Stressed, Anxious, Overwhelmed..."
      // stack the issue found on-device. A `find.byType(Wrap)` check passed
      // throughout that bug (#11, #15 both shipped with it in place), so
      // these compare rendered row position instead -- the same `dy`
      // meaning "the same Wrap row" that a real thumb would see.
      testWidgets(
        'two feelings in the same group sheet share a row at 360dp',
        (tester) async {
          tester.view.physicalSize = const Size(360, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(const _Harness());
          await tester.tap(find.text('Uplifted'));
          await tester.pumpAndSettle();

          final happyTop = tester.getTopLeft(find.text('Happy'));
          final excitedTop = tester.getTopLeft(find.text('Excited'));
          expect(
            excitedTop.dy,
            happyTop.dy,
            reason:
                'Happy and Excited are both short words and must share the '
                'Uplifted section\'s first Wrap row at 360dp; one full-width '
                'chip per row would put Excited on a row of its own below',
          );
          expect(excitedTop.dx, greaterThan(happyTop.dx));
        },
      );

      testWidgets(
        'two chosen feelings in the summary row above the groups also '
        'share a row at 360dp',
        (tester) async {
          tester.view.physicalSize = const Size(360, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            const _Harness(initial: [happy, excited]),
          );

          final happyTop = tester.getTopLeft(find.text('Happy'));
          final excitedTop = tester.getTopLeft(find.text('Excited'));
          expect(
            excitedTop.dy,
            happyTop.dy,
            reason:
                'the chosen-feelings row above the group chips is the other '
                'call site #111 named; it must wrap exactly like the sheet '
                'does',
          );
          expect(excitedTop.dx, greaterThan(happyTop.dx));
        },
      );

      testWidgets(
        'no overflow at 360dp and 2x text scale once long labels sit '
        'side by side',
        (tester) async {
          tester.view.physicalSize = const Size(360, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          // Chips sharing a row is new as of this fix, and it halves (or
          // worse) the line width each one gets -- a condition the old
          // one-chip-per-row layout never exercised, however long the word.
          // "Affectionate"/"Overwhelmed"/"Disappointed" are the app's longest
          // feeling words, and 2x is the accessibility ceiling `pattern_echo_
          // panel_test.dart` and `when_panel_test.dart` already check other
          // widgets against.
          await tester.pumpWidget(
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const _Harness(groups: longLabelGroups),
            ),
          );
          await tester.tap(find.text('Uplifted'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        },
      );
    },
  );
}
