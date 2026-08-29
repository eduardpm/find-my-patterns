import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:find_my_patterns/core/widgets/feeling_accent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const journal = JournalColors(
    surface: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFFFFFFF),
    onSurface: Color(0xFF000000),
    onSurfaceVariant: Color(0xFF000000),
    primary: Color(0xFF000000),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFFFFF),
    accent: Color(0xFF000000),
    accentContainer: Color(0xFFFFFFFF),
    outline: Color(0xFF000000),
    hairline: Color(0xFF000000),
    error: Color(0xFF000000),
    errorContainer: Color(0xFFFFFFFF),
    onErrorContainer: Color(0xFF000000),
    success: Color(0xFF000000),
    successContainer: Color(0xFFFFFFFF),
    feelings: FeelingColors(
      uplifted: Color(0xFF111111),
      steady: Color(0xFF222222),
      tense: Color(0xFF333333),
      low: Color(0xFF444444),
    ),
    isDark: false,
  );

  group('FeelingAccent', () {
    test('resolves through the feeling group key when it is recognised', () {
      const feeling = Feeling('happy', 'Happy', Valence.positive, 'uplifted');
      expect(feeling.accent(journal), journal.feelings.uplifted);
    });

    test('falls back to the valence when the group is unrecognised', () {
      const feeling = Feeling(
        'brand_new',
        'New',
        Valence.negative,
        'never_seen',
      );
      expect(feeling.accent(journal), journal.feelings.low);
    });
  });

  group('FeelingGroupAccent', () {
    test('resolves through its own key when it is recognised', () {
      const group = FeelingGroup('tense', 'Tense', Valence.negative, []);
      expect(group.accent(journal), journal.feelings.tense);
    });

    test('falls back to the valence when the key is unrecognised', () {
      const group = FeelingGroup(
        'never_seen',
        'Mystery',
        Valence.positive,
        [],
      );
      expect(group.accent(journal), journal.feelings.uplifted);
    });
  });
}
