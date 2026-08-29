import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Valence', () {
    test('fromWire resolves the known values, case-insensitively', () {
      expect(Valence.fromWire('positive'), Valence.positive);
      expect(Valence.fromWire('NEUTRAL'), Valence.neutral);
      expect(Valence.fromWire('Negative'), Valence.negative);
    });

    test('fromWire never throws: unrecognised or null is unknown', () {
      expect(Valence.fromWire('sideways'), Valence.unknown);
      expect(Valence.fromWire(null), Valence.unknown);
      expect(Valence.fromWire(''), Valence.unknown);
    });
  });

  group('Feeling', () {
    test('emoji is looked up by key', () {
      const feeling = Feeling('happy', 'Happy', Valence.positive, 'uplifted');
      expect(feeling.emoji, '😊');
    });

    test('toString names the key, for debugging', () {
      const feeling = Feeling('happy', 'Happy', Valence.positive, 'uplifted');
      expect(feeling.toString(), 'Feeling(happy)');
    });

    test('emoji falls back for an unknown key', () {
      const feeling = Feeling('brand_new', 'New', Valence.unknown, '');
      expect(feeling.emoji, FeelingEmoji.fallback);
    });
  });

  group('FeelingEmoji', () {
    test('forKey resolves every one of the 31 seeded keys', () {
      const expected = {
        'happy': '😊',
        'excited': '🤩',
        'grateful': '🙏',
        'proud': '😌',
        'hopeful': '🌱',
        'energised': '⚡',
        'affectionate': '🤗',
        'playful': '😄',
        'neutral': '😐',
        'calm': '🌊',
        'content': '🙂',
        'relaxed': '😎',
        'focused': '🎯',
        'curious': '🤔',
        'indifferent': '😶',
        'stressed': '😖',
        'anxious': '😰',
        'overwhelmed': '😵',
        'frustrated': '😤',
        'irritable': '😠',
        'angry': '😡',
        'restless': '😬',
        'guilty': '😞',
        'sad': '😢',
        'depressed': '😔',
        'lonely': '🥺',
        'disappointed': '😞',
        'hopeless': '😩',
        'numb': '😑',
        'sleepy': '😴',
        'exhausted': '🥱',
      };
      expect(expected.length, 31);
      for (final entry in expected.entries) {
        expect(FeelingEmoji.forKey(entry.key), entry.value);
      }
    });

    test('forKey falls back for an unrecognised key', () {
      expect(FeelingEmoji.forKey('nope'), FeelingEmoji.fallback);
      expect(FeelingEmoji.fallback, '🙂');
    });
  });

  group('FeelingGroup', () {
    test('holds its feelings', () {
      const group = FeelingGroup('uplifted', 'Uplifted', Valence.positive, [
        Feeling('happy', 'Happy', Valence.positive, 'uplifted'),
      ]);
      expect(group.feelings.single.key, 'happy');
    });

    test('equality and hashCode compare every field, feelings included', () {
      const happy = Feeling('happy', 'Happy', Valence.positive, 'uplifted');
      const sad = Feeling('sad', 'Sad', Valence.negative, 'low');
      const group = FeelingGroup('uplifted', 'Uplifted', Valence.positive, [
        happy,
      ]);
      const sameShape = FeelingGroup('uplifted', 'Uplifted', Valence.positive, [
        happy,
      ]);
      const differentLabel = FeelingGroup(
        'uplifted',
        'Steady',
        Valence.positive,
        [happy],
      );
      const differentFeelings = FeelingGroup(
        'uplifted',
        'Uplifted',
        Valence.positive,
        [sad],
      );
      const differentLength = FeelingGroup(
        'uplifted',
        'Uplifted',
        Valence.positive,
        [happy, sad],
      );

      expect(group, sameShape);
      expect(group.hashCode, sameShape.hashCode);
      expect(group, isNot(differentLabel));
      expect(group, isNot(differentFeelings));
      expect(group, isNot(differentLength));
    });
  });

  group('FeelingCatalog', () {
    const happy = Feeling('happy', 'Happy', Valence.positive, 'uplifted');
    const sad = Feeling('sad', 'Sad', Valence.negative, 'low');
    final catalog = FeelingCatalog([happy, sad]);

    test('fromKey resolves a known key', () {
      expect(catalog.fromKey('happy'), happy);
    });

    test('fromKey returns null for an unknown or null key', () {
      expect(catalog.fromKey('invented'), isNull);
      expect(catalog.fromKey(null), isNull);
    });

    test('fromKeys drops unknown keys rather than inventing them', () {
      expect(catalog.fromKeys(['happy', 'invented', 'sad']), [happy, sad]);
    });

    test('fromKeys preserves order and duplicates', () {
      expect(catalog.fromKeys(['sad', 'happy', 'sad']), [sad, happy, sad]);
    });

    test('empty is a usable catalog with nothing in it', () {
      expect(FeelingCatalog.empty.feelings, isEmpty);
      expect(FeelingCatalog.empty.groups, isEmpty);
      expect(FeelingCatalog.empty.fromKey('happy'), isNull);
    });

    test('groups default to empty', () {
      expect(catalog.groups, isEmpty);
    });
  });

  test('kMaxFeelingsPerEntry matches the backend ceiling', () {
    expect(kMaxFeelingsPerEntry, 4);
  });
}
