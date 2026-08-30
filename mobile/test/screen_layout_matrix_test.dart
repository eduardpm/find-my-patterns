import 'package:flutter_test/flutter_test.dart';

import 'support/dynamic_type_matrix.dart';
import 'support/screen_registry.dart';
import 'support/screens/auth_premium.dart';
import 'support/screens/compose_entry.dart';
import 'support/screens/core_widgets.dart';
import 'support/screens/experiments.dart';
import 'support/screens/insights.dart';
import 'support/screens/settings_shell.dart';
import 'support/screens/today_calendar.dart';

/// The whole-app layout sweep: every registered surface, at every cell of the
/// dynamic-type matrix, against the three invariants in
/// `support/dynamic_type_matrix.dart`.
///
/// **Why this file exists.** Before it, dynamic-type coverage was opt-in and
/// per-screen: seventeen hand-written test files, each added by whichever
/// ticket happened to be auditing that screen, out of forty-six widget-bearing
/// files. A screen nobody had audited had no coverage, and *nothing told you
/// which screens those were*. Eighteen instances of one layout bug family have
/// shipped that way (#108, #111, #115, #117, #131, #137, #141, #150, and ten
/// more across #155's three splits), each found by a person looking at one
/// screen, each fixed as its own ticket. This turns that from "N future
/// tickets" into "one failing test with N cases".
///
/// Two halves make it work:
///
/// 1. [_areas] — the surfaces that are swept, each checked at 320/360dp x
///    1.0/1.3/2.0.
/// 2. `every widget file is accounted for` — a guard that walks `lib/` and
///    fails when a widget file is neither registered, nor covered by its own
///    `TextScaler` test, nor named in an area's `unswept` set. A new screen
///    cannot be added without someone deciding which it is, so the gap can
///    never silently reopen.
///
/// The union of the areas' `unswept` sets is the visible backlog. Shrinking it
/// is the work; it must never grow.
///
/// **A known weakness, stated rather than hidden.** The guard accepts a file's
/// own `TextScaler` test as coverage, which is how the seventeen per-screen
/// tests that predate this sweep are accounted for. That allowance is weaker
/// evidence than being registered here, and #163 is the proof: `pattern_card`'s
/// own dynamic-type test passes while the card overflows inside the real
/// `InsightsScreen`, because its harness gives the card more width than the
/// screen's padding leaves it. A dedicated test proves what its author thought
/// to build; a `ScreenCase` proves the surface as the app assembles it. Those
/// seventeen files should eventually be registered here too — until they are,
/// read "accounted for" as "someone has looked", not "measured".
///
/// **Adding surfaces:** edit the one file under `support/screens/` that owns
/// the area, never this file. That is what lets several batches of this work
/// run at once without colliding.
final _areas = [
  authPremium,
  composeEntry,
  coreWidgets,
  experiments,
  insights,
  settingsShell,
  todayCalendar,
];

void main() {
  final cases = [for (final area in _areas) ...area.cases];
  final unswept = <String>{for (final area in _areas) ...area.unswept};

  for (final screen in cases) {
    group('${screen.name} layout invariants', () {
      for (final width in kMatrixWidths) {
        for (final scale in kMatrixScales) {
          final known = screen.knownFailures['${width.toInt()}x$scale'];
          // The issue number goes in the test *name*, not into `skip` --
          // `testWidgets` takes only a bool there, and a skipped case whose
          // name does not say why is indistinguishable from one nobody wrote.
          final label = known == null
              ? '${width.toInt()}dp / ${scale}x'
              : '${width.toInt()}dp / ${scale}x (known defect $known)';
          testWidgets(label, (tester) async {
            await pumpMatrixCell(
              tester,
              screen.build(),
              width: width,
              scale: scale,
            );
            expectNoLayoutViolations(tester, width: width);
          }, skip: known != null);
        }
      }
    });
  }

  test('every widget file is accounted for', () {
    final registered = {for (final screen in cases) screen.source};
    final unaccounted = [
      for (final relative in widgetSources())
        if (!registered.contains(relative) &&
            !hasDedicatedMatrixTest(relative) &&
            !unswept.contains(relative))
          relative,
    ];

    expect(
      unaccounted,
      isEmpty,
      reason:
          'These widget files have no dynamic-type coverage of any kind. For '
          'each, either add a ScreenCase to the owning file under '
          'test/support/screens/ (preferred), or write a dedicated '
          '<name>_test.dart exercising TextScaler, or add it to that area\'s '
          "unswept set with a reason. See this file's doc comment.",
    );
  });

  test('the unswept backlog stays honest', () {
    final registered = {for (final screen in cases) screen.source};
    expect(
      unswept.intersection(registered),
      isEmpty,
      reason: 'A surface swept here must be removed from the unswept backlog.',
    );
    expect(
      unswept.where(hasDedicatedMatrixTest),
      isEmpty,
      reason:
          'A surface that has grown its own dynamic-type test must be removed '
          'from the unswept backlog.',
    );
    expect(
      unswept.difference(widgetSources().toSet()),
      isEmpty,
      reason:
          'The backlog names a file that no longer exists or no longer builds '
          'widgets. Remove it.',
    );
  });

  test('no surface is registered by two areas', () {
    final seen = <String, String>{};
    final duplicates = <String>[];
    for (final area in _areas) {
      for (final screen in area.cases) {
        final owner = seen[screen.source];
        if (owner != null) {
          duplicates.add('${screen.source} in both $owner and ${area.name}');
        }
        seen[screen.source] = area.name;
      }
    }
    expect(duplicates, isEmpty);
  });
}
