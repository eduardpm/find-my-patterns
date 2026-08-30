import '../screen_registry.dart';

/// `lib/features/settings/ and lib/features/shell/`.
final settingsShell = ScreenArea(
  name: 'settings shell',
  cases: [],
  unswept: const {
    'features/settings/digest_card.dart',
    'features/settings/export/export_row.dart',
    'features/settings/reminders_card.dart',
    'features/settings/settings_screen.dart',
    'features/shell/app_shell.dart',
  },
);
