import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/widgets/premium_lock.dart';
import 'package:flutter/material.dart';

import '../screen_registry.dart';

/// `lib/core/widgets/` and the app root.
final coreWidgets = ScreenArea(
  name: 'core widgets',
  cases: [
    ScreenCase(
      name: 'PremiumLock',
      source: 'core/widgets/premium_lock.dart',
      build: () => MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(
          body: PremiumLock(message: 'Weekly digests are a Premium feature.'),
        ),
      ),
    ),
  ],
  unswept: const {
    // Paint no text of their own; nothing for the invariants to check.
    'app.dart',
    'core/widgets/journal_dashed_border.dart',
    'core/widgets/journal_page_wash.dart',
    'core/widgets/journal_scrollbar.dart',

    // Real surfaces, never measured.
    'core/widgets/feature_placeholder.dart',
    'core/widgets/journal.dart',
    'core/widgets/status_views.dart',
    // Swept transitively by `LoginScreen`, which is where its known #169
    // failure is recorded. Registering it standalone would duplicate that.
    'core/widgets/server_form.dart',
  },
);
