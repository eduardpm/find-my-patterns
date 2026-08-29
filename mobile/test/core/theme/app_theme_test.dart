import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Article 3: no assertions on colour values. What matters here is the
  // mapping — that a stored setting selects the theme it names, that a
  // chosen palette is the one that gets wired into the theme, and that the
  // two builders produce opposite brightnesses. The palette itself is
  // verified by looking at the app (Article 5).
  test('the builders produce a light and a dark theme', () {
    expect(buildLightTheme().colorScheme.brightness, Brightness.light);
    expect(buildDarkTheme().colorScheme.brightness, Brightness.dark);
  });

  test('the builders default to the default palette', () {
    expect(
      buildLightTheme().extension<JournalColors>(),
      JournalPalette.defaultPalette.light,
    );
    expect(
      buildDarkTheme().extension<JournalColors>(),
      JournalPalette.defaultPalette.dark,
    );
  });

  test('the builders attach the chosen palette as a theme extension', () {
    expect(
      buildLightTheme(palette: JournalPalette.sage).extension<JournalColors>(),
      JournalPalette.sage.light,
    );
    expect(
      buildDarkTheme(palette: JournalPalette.dusk).extension<JournalColors>(),
      JournalPalette.dusk.dark,
    );
  });

  test('every stored setting maps to the Flutter mode it names', () {
    expect(
      themeModeSettingToMaterial(ThemeModeSetting.system),
      ThemeMode.system,
    );
    expect(themeModeSettingToMaterial(ThemeModeSetting.light), ThemeMode.light);
    expect(themeModeSettingToMaterial(ThemeModeSetting.dark), ThemeMode.dark);
  });

  group('BuildContext.journalColors', () {
    testWidgets('reads the palette attached to the ambient theme', (
      tester,
    ) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(palette: JournalPalette.dusk),
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(capturedContext.journalColors, JournalPalette.dusk.light);
    });

    testWidgets(
      'falls back to the default palette when no extension is attached',
      (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(
          capturedContext.journalColors,
          JournalPalette.defaultPalette.dark,
        );
      },
    );
  });
}
