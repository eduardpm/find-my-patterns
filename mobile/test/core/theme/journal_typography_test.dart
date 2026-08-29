import 'package:find_my_patterns/core/theme/journal_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Article 3: no assertions on font sizes or exact styling. What matters
  // here is behaviour — that upper-casing is applied for display, that it
  // never mutates the caller's string, and that tabular figures are
  // requested through a font feature rather than silently dropped.

  group('JournalType.eyebrowCase', () {
    test('upper-cases the given text', () {
      expect(JournalType.eyebrowCase('Monday, August 24'), 'MONDAY, AUGUST 24');
    });

    test('does not mutate the original string', () {
      const original = 'three entries';
      JournalType.eyebrowCase(original);
      expect(original, 'three entries');
    });
  });

  group('JournalType.tabularFigures', () {
    test('adds the tnum font feature to the given style', () {
      const style = TextStyle(fontSize: 14);
      final result = JournalType.tabularFigures(style);
      expect(result.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    test('preserves the rest of the style', () {
      const style = TextStyle(fontSize: 14, fontWeight: FontWeight.bold);
      final result = JournalType.tabularFigures(style);
      expect(result.fontSize, 14);
      expect(result.fontWeight, FontWeight.bold);
    });
  });

  group('buildJournalTextTheme', () {
    test('fills every slot the theme relies on', () {
      final textTheme = buildJournalTextTheme();
      expect(textTheme.displaySmall, isNotNull);
      expect(textTheme.headlineSmall, isNotNull);
      expect(textTheme.titleLarge, isNotNull);
      expect(textTheme.titleMedium, isNotNull);
      expect(textTheme.bodyLarge, isNotNull);
      expect(textTheme.bodyMedium, isNotNull);
      expect(textTheme.labelLarge, isNotNull);
      expect(textTheme.labelMedium, isNotNull);
      expect(textTheme.labelSmall, isNotNull);
    });
  });
}
