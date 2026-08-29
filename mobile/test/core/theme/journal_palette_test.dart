import 'package:find_my_patterns/core/theme/journal_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeelingColors', () {
    const colors = FeelingColors(
      uplifted: Color(0xFF111111),
      steady: Color(0xFF222222),
      tense: Color(0xFF333333),
      low: Color(0xFF444444),
    );

    test('forGroupKey resolves every known group to its own accent', () {
      expect(colors.forGroupKey('uplifted'), colors.uplifted);
      expect(colors.forGroupKey('steady'), colors.steady);
      expect(colors.forGroupKey('tense'), colors.tense);
      expect(colors.forGroupKey('low'), colors.low);
    });

    test('forGroupKey returns null for an unrecognised or absent group', () {
      expect(colors.forGroupKey('nostalgic'), isNull);
      expect(colors.forGroupKey(null), isNull);
    });

    test('forValenceId maps positive and negative, and defaults to steady', () {
      expect(colors.forValenceId('positive'), colors.uplifted);
      expect(colors.forValenceId('negative'), colors.low);
      expect(colors.forValenceId('neutral'), colors.steady);
      expect(colors.forValenceId(null), colors.steady);
    });

    test('forFeeling prefers the group key over the valence fallback', () {
      expect(
        colors.forFeeling(groupKey: 'tense', valenceId: 'positive'),
        colors.tense,
      );
    });

    test(
      'forFeeling falls back to the valence when the group is unrecognised',
      () {
        expect(
          colors.forFeeling(groupKey: 'nostalgic', valenceId: 'negative'),
          colors.low,
        );
      },
    );

    test('forFeeling falls back to steady when nothing is given', () {
      expect(colors.forFeeling(), colors.steady);
    });

    test('copyWith replaces only what it is given', () {
      final replaced = colors.copyWith(uplifted: colors.low);
      expect(replaced.uplifted, colors.low);
      expect(replaced.steady, colors.steady);
      expect(replaced.tense, colors.tense);
      expect(replaced.low, colors.low);
    });
  });

  group('JournalColors', () {
    test('copyWith replaces only what it is given', () {
      final light = JournalPalette.paper.light;
      final replaced = light.copyWith(isDark: true);
      expect(replaced.isDark, isTrue);
      expect(replaced.surface, light.surface);
      expect(replaced.feelings, light.feelings);
    });

    test('lerp with a foreign extension type returns the original', () {
      final light = JournalPalette.paper.light;
      expect(light.lerp(null, 0.5), same(light));
    });

    test('lerp reports isDark from whichever half t is closer to', () {
      final light = JournalPalette.paper.light;
      final dark = JournalPalette.paper.dark;
      expect(light.lerp(dark, 0).isDark, light.isDark);
      expect(light.lerp(dark, 1).isDark, dark.isDark);
    });
  });

  group('JournalPalette', () {
    test('fromId resolves every known id', () {
      expect(JournalPalette.fromId('paper'), JournalPalette.paper);
      expect(JournalPalette.fromId('sage'), JournalPalette.sage);
      expect(JournalPalette.fromId('dusk'), JournalPalette.dusk);
    });

    test('fromId falls back to the default for anything else', () {
      expect(JournalPalette.fromId('midnight'), JournalPalette.defaultPalette);
      expect(JournalPalette.fromId(null), JournalPalette.defaultPalette);
    });

    test('the default palette is paper', () {
      expect(JournalPalette.defaultPalette, JournalPalette.paper);
    });

    test('colors selects the half matching dark', () {
      for (final palette in JournalPalette.values) {
        expect(palette.colors(dark: false), palette.light);
        expect(palette.colors(dark: true), palette.dark);
        expect(palette.light.isDark, isFalse);
        expect(palette.dark.isDark, isTrue);
      }
    });

    test('every palette has an id, a label and a description', () {
      for (final palette in JournalPalette.values) {
        expect(palette.id, isNotEmpty);
        expect(palette.label, isNotEmpty);
        expect(palette.description, isNotEmpty);
      }
    });

    test('every id is unique and stable', () {
      final ids = JournalPalette.values.map((p) => p.id).toSet();
      expect(ids, {'paper', 'sage', 'dusk'});
    });
  });
}
