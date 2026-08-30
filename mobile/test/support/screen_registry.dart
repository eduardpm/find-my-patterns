import 'dart:io';

import 'package:flutter/material.dart';

/// One surface the whole-app layout sweep checks, and where it lives.
///
/// Registered in one of the per-area files under `screens/`, never here — see
/// `screens/README` in this file's own doc below for why the registry is split
/// by area rather than kept in one list.
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
  /// Deliberately *not* silent: the issue number goes into the test's own name,
  /// so a known defect stays visible in the output instead of vanishing the way
  /// an unwritten test does. Every entry is a debt — an empty map is the goal.
  final Map<String, String> knownFailures;
}

/// One area's contribution to the sweep: what it covers, and what it does not
/// cover yet.
///
/// **The registry is split by area so that several people — or several agents —
/// can extend it at once without colliding.** Every batch of surfaces edits
/// exactly one file under `screens/`; this file and
/// `test/screen_layout_matrix_test.dart` never change while that work happens.
class ScreenArea {
  /// Declares an area named [name] covering [cases], still owing [unswept].
  const ScreenArea({
    required this.name,
    required this.cases,
    required this.unswept,
  });

  /// The area's human name, for the guard's failure messages.
  final String name;

  /// The surfaces this area sweeps.
  final List<ScreenCase> cases;

  /// Widget files in this area that the sweep does **not** yet cover.
  ///
  /// The visible backlog. An entry earns its place only until someone writes a
  /// [ScreenCase] for it; a file that paints no text says so and stays.
  final Set<String> unswept;
}

/// Every `lib/`-relative path that declares a widget.
Iterable<String> widgetSources() sync* {
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
/// tomorrow should stop being reported without anyone editing a list here.
bool hasDedicatedMatrixTest(String relative) {
  final file = File(
    'test/${relative.replaceFirst(RegExp(r'\.dart$'), '')}_test.dart',
  );
  return file.existsSync() && file.readAsStringSync().contains('TextScaler');
}
