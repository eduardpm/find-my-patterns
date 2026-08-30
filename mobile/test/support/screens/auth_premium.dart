import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/features/auth/login_screen.dart';
import 'package:find_my_patterns/features/premium/upgrade_screen.dart';
import 'package:flutter/material.dart';

import '../harness.dart';
import '../screen_registry.dart';

/// `lib/features/auth/` and `lib/features/premium/`.
final authPremium = ScreenArea(
  name: 'auth and premium',
  cases: [
    ScreenCase(
      name: 'UpgradeScreen',
      source: 'features/premium/upgrade_screen.dart',
      build: () =>
          MaterialApp(theme: buildLightTheme(), home: const UpgradeScreen()),
    ),
    ScreenCase(
      name: 'LoginScreen',
      source: 'features/auth/login_screen.dart',
      build: () => Harness().scope(
        MaterialApp(theme: buildLightTheme(), home: const LoginScreen()),
      ),
      // `server_form.dart`'s scheme `SegmentedButton` cannot fit "HTTPS" at
      // 2x: two segments need more width than a 320dp screen has, whatever
      // their padding. Needs a control change, not a tweak.
      knownFailures: const {'320x2.0': '#169'},
    ),
  ],
  unswept: const {},
);
