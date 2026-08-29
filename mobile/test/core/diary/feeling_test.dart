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
    test('toString names the key, for debugging', () {
      const feeling = Feeling('happy', 'Happy', Valence.positive, 'uplifted');
      expect(feeling.toString(), 'Feeling(happy)');
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
