import 'dart:io';

import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/entry.dart';
import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/features/auth/login_screen.dart';
import 'package:find_my_patterns/features/premium/upgrade_screen.dart';
import 'package:find_my_patterns/features/today/entry_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/dynamic_type_matrix.dart';
import 'support/harness.dart';

/// The whole-app layout sweep: every registered surface, at every cell of the
/// dynamic-type matrix, against the three invariants in
/// `support/dynamic_type_matrix.dart`.
///
/// **Why this file exists.** Before it, dynamic-type coverage was opt-in and
/// per-screen: 17 hand-written test files, each added by whichever ticket
/// happened to be auditing that screen, out of 46 widget-bearing files. A
/// screen nobody had audited had no coverage, and *nothing told you which
/// screens those were*. Eighteen instances of one layout bug family have
/// shipped that way (#108, #111, #115, #117, #131, #137, #141, #150, and ten
/// more in #155), each found by a person looking at one screen, each fixed as
/// its own ticket.
///
/// This turns that from "N future tickets" into "one failing test with N
/// cases". Two halves make it work:
///
/// 1. [_registry] — the surfaces that are swept, each checked at
///    320/360dp x 1.0/1.3/2.0.
/// 2. [`every widget file is accounted for`] — a guard that walks `lib/` and
///    fails when a widget file is neither registered here nor named in
///    [kUnsweptSurfaces]. A new screen cannot be added without someone
///    deciding which it is, so the gap can never silently reopen.
///
/// [kUnsweptSurfaces] is therefore the visible backlog. Shrinking it is the
/// work; it must never grow.
class ScreenCase {
  /// Registers [build] under [name], implemented by `lib/`-relative [source].
  const ScreenCase({
    required this.name,
    required this.source,
    required this.build,
    this.knownFailures = const {},
  });

  /// How this surface is named in test output.
  final String name;

  /// The `lib/`-relative file this surface exercises, for the coverage guard.
  final String source;

  /// Builds the surface, already wrapped in whatever app scaffolding it needs.
  final Widget Function() build;

  /// Matrix cells this surface is known to fail, keyed `'<width>x<scale>'`,
  /// each mapped to the issue tracking it.
  ///
  /// Deliberately *not* silent: a skipped cell still appears in the test
  /// output with its issue number, so a known defect stays visible instead of
  /// vanishing the way an unwritten test does. Every entry is a debt — an
  /// empty map is the goal.
  final Map<String, String> knownFailures;
}

Widget _app(Widget child) => MaterialApp(
  theme: buildLightTheme(),
  home: Scaffold(body: child),
);

const _feelings = [
  Feeling('relaxed', 'Relaxed', Valence.positive, 'uplifted'),
  Feeling('curious', 'Curious', Valence.neutral, 'steady'),
  Feeling('irritable', 'Irritable', Valence.negative, 'tense'),
];

/// An entry carrying three feelings and a long body — the shape a real diary
/// produces, and the one that stresses a row of feeling chips hardest.
Entry _entry() => entryFromJson({
  'id': 'entry-1',
  'created_at': '2026-08-01T10:17:00',
  'entry_date': CalendarDate(2026, 8, 1).toString(),
  'mode': 'freeform',
  'raw_text':
      'Slept badly and woke up several times, then the morning got better.',
  'feeling_key': 'relaxed',
  'feeling_keys': ['relaxed', 'curious', 'irritable'],
  'feeling_source': 'confirmed',
  'version': 1,
  'analysis_pending': false,
}, const FeelingCatalog(_feelings));

final _registry = <ScreenCase>[
  ScreenCase(
    name: 'UpgradeScreen',
    source: 'features/premium/upgrade_screen.dart',
    build: () => MaterialApp(
      theme: buildLightTheme(),
      home: const UpgradeScreen(),
    ),
  ),
  ScreenCase(
    name: 'LoginScreen',
    source: 'features/auth/login_screen.dart',
    build: () => Harness().scope(
      MaterialApp(theme: buildLightTheme(), home: const LoginScreen()),
    ),
    // `server_form.dart`'s scheme `SegmentedButton` cannot fit "HTTPS" at
    // 2x: two segments need more width than a 320dp screen has, whatever
    // their padding. Needs a control change, not a tweak -- see the issue.
    knownFailures: const {'320x2.0': '#169'},
  ),
  ScreenCase(
    name: 'EntryCard',
    source: 'features/today/entry_card.dart',
    build: () => _app(EntryCard(entry: _entry(), onTap: () {})),
  ),
];

/// Widget-bearing files under `lib/` that this sweep does **not** yet cover.
///
/// Every entry is a surface whose layout has never been measured at the
/// matrix. This list is the backlog, not a permanent exemption: an entry
/// earns its place only until someone writes a [ScreenCase] for it.
///
/// Some genuinely never need one — a file that paints no text cannot violate
/// any of the three invariants — and those say so.
const kUnsweptSurfaces = <String>{
  // Paint no text of their own; nothing for the invariants to check.
  'core/widgets/journal_dashed_border.dart',
  'core/widgets/journal_page_wash.dart',
  'core/widgets/journal_scrollbar.dart',
  'app.dart',

  // Real surfaces, never measured. Tracked: #165 covers the two compose ones,
  // #163 covers pattern_card.dart.
  'core/widgets/feature_placeholder.dart',
  'core/widgets/journal.dart',
  'core/widgets/premium_lock.dart',
  'core/widgets/server_form.dart',
  'core/widgets/status_views.dart',
  'features/calendar/year_grid.dart',
  'features/compose/first_pattern_card.dart',
  'features/compose/guided_question_flow.dart',
  'features/compose/insight_progress_panel.dart',
  'features/compose/voice_answer_recorder.dart',
  'features/experiments/active_experiment_banner.dart',
  'features/experiments/comparison_bars.dart',
  'features/experiments/experiment_results_screen.dart',
  'features/experiments/experiment_setup_sheet.dart',
  'features/insights/charts/mood_trend_chart.dart',
  'features/insights/digest_screen.dart',
  'features/insights/weak_signal_row.dart',
  'features/insights/withdrawal_notice.dart',
  'features/settings/digest_card.dart',
  'features/settings/export/export_row.dart',
  'features/settings/reminders_card.dart',
  'features/settings/settings_screen.dart',
  'features/shell/app_shell.dart',
  'features/today/writing_streak_line.dart',
};

/// Every `lib/`-relative path that declares a widget.
Iterable<String> _widgetSources() sync* {
  final widgetPattern = RegExp(
    r'extends (StatelessWidget|StatefulWidget|ConsumerWidget'
    r'|ConsumerStatefulWidget)',
  );
  for (final file in Directory('lib').listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    if (!widgetPattern.hasMatch(file.readAsStringSync())) continue;
    yield file.path.substring('lib/'.length);
  }
}

/// Whether [relative] already has its own test exercising a [TextScaler].
///
/// Detected rather than listed by hand: the seventeen per-screen dynamic-type
/// tests that predate this sweep are real coverage, and a file that grows one
/// tomorrow should stop being reported without anyone remembering to edit a
/// list here.
bool _hasDedicatedMatrixTest(String relative) {
  final file = File(
    'test/${relative.replaceFirst(RegExp(r'\.dart$'), '')}_test.dart',
  );
  return file.existsSync() && file.readAsStringSync().contains('TextScaler');
}

void main() {
  for (final screen in _registry) {
    group('${screen.name} layout invariants', () {
      for (final width in kMatrixWidths) {
        for (final scale in kMatrixScales) {
          final cell = '${width.toInt()}x$scale';
          final known = screen.knownFailures[cell];
          // The issue number goes in the test *name*, not into `skip` --
          // `testWidgets` takes only a bool there, and a skipped case whose
          // name does not say why is indistinguishable from one nobody
          // wrote.
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
    final registered = {for (final screen in _registry) screen.source};
    final unaccounted = <String>[];
    for (final relative in _widgetSources()) {
      if (registered.contains(relative)) continue;
      if (_hasDedicatedMatrixTest(relative)) continue;
      if (kUnsweptSurfaces.contains(relative)) continue;
      unaccounted.add(relative);
    }

    expect(
      unaccounted,
      isEmpty,
      reason:
          'These widget files have no dynamic-type coverage of any kind. For '
          'each, either add a ScreenCase above (preferred), or write a '
          'dedicated <name>_test.dart exercising TextScaler, or add it to '
          "kUnsweptSurfaces with a reason. See this file's doc comment.",
    );
  });

  test('kUnsweptSurfaces stays honest', () {
    final registered = {for (final screen in _registry) screen.source};
    expect(
      kUnsweptSurfaces.intersection(registered),
      isEmpty,
      reason: 'A surface swept here must be removed from the unswept backlog.',
    );
    expect(
      kUnsweptSurfaces.where(_hasDedicatedMatrixTest),
      isEmpty,
      reason:
          'A surface that has grown its own dynamic-type test must be removed '
          'from the unswept backlog.',
    );
    expect(
      kUnsweptSurfaces.difference(_widgetSources().toSet()),
      isEmpty,
      reason:
          'kUnsweptSurfaces names a file that no longer exists or no longer '
          'builds widgets. Remove it.',
    );
  });
}
