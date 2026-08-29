// #40's display rule: hidden below two days, muted rather than
// celebratory in every theme, and carrying its own spoken label.

import 'package:find_my_patterns/core/theme/app_theme.dart';
import 'package:find_my_patterns/features/today/writing_streak_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpLine(
    WidgetTester tester,
    int streakDays, {
    bool dark = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(body: WritingStreakLine(streakDays: streakDays)),
      ),
    );
  }

  group('the visibility threshold', () {
    testWidgets('renders nothing at zero days', (tester) async {
      await pumpLine(tester, 0);
      expect(find.byType(WritingStreakLine), findsOneWidget);
      expect(find.byType(Text), findsNothing);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('renders nothing at one day -- not a pattern yet', (
      tester,
    ) async {
      await pumpLine(tester, 1);
      expect(find.byType(Text), findsNothing);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('shows at two days', (tester) async {
      await pumpLine(tester, 2);
      expect(find.text('2 days writing'), findsOneWidget);
    });

    testWidgets('shows a larger streak, e.g. twelve days', (tester) async {
      await pumpLine(tester, 12);
      expect(find.text('12 days writing'), findsOneWidget);
    });
  });

  group('semantics', () {
    testWidgets('speaks "Writing streak: 12 days" and hides the raw text '
        'node from the tree', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLine(tester, 12);

      expect(
        tester.getSemantics(find.byType(WritingStreakLine)),
        matchesSemantics(label: 'Writing streak: 12 days'),
      );
      handle.dispose();
    });
  });

  group('muted rendering', () {
    testWidgets('the icon and text both use onSurfaceVariant in light', (
      tester,
    ) async {
      await pumpLine(tester, 5);
      final context = tester.element(find.byType(WritingStreakLine));
      final journal = context.journalColors;

      final icon = tester.widget<Icon>(find.byType(Icon));
      final text = tester.widget<Text>(find.text('5 days writing'));
      expect(icon.color, journal.onSurfaceVariant);
      expect(text.style?.color, journal.onSurfaceVariant);
      // Muted, not the primary/accent colour a celebratory treatment would
      // reach for.
      expect(icon.color, isNot(Theme.of(context).colorScheme.primary));
    });

    testWidgets('the icon and text both use onSurfaceVariant in dark too', (
      tester,
    ) async {
      await pumpLine(tester, 5, dark: true);
      final context = tester.element(find.byType(WritingStreakLine));
      final journal = context.journalColors;

      final icon = tester.widget<Icon>(find.byType(Icon));
      final text = tester.widget<Text>(find.text('5 days writing'));
      expect(icon.color, journal.onSurfaceVariant);
      expect(text.style?.color, journal.onSurfaceVariant);
    });

    testWidgets('draws no fire/badge iconography -- a plain writing icon '
        'only', (tester) async {
      await pumpLine(tester, 5);
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, isNot(Icons.local_fire_department));
      expect(icon.icon, isNot(Icons.emoji_events));
    });
  });
}
