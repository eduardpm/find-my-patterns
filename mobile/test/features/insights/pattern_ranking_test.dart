// UX-2: the pure ranking function behind the Insights feed. No widget, no
// `BuildContext` -- a list of patterns in, two ordered lists out.

import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/features/insights/pattern_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  group('rankPatterns', () {
    test(
      'a badge-less pattern -- undefined lift, per P0-6 -- lands in weak, '
      'never confirmed',
      () {
        final ranking = rankPatterns([
          buildPattern(id: 'p1', direction: PatternDirection.none, lift: null),
        ]);

        expect(ranking.confirmed, isEmpty);
        expect(ranking.weak.map((p) => p.id), ['p1']);
      },
    );

    test(
      'a badge-less pattern whose lift is defined but below the minimum -- '
      'still `none` per the backend`s own badgeDirectionFor -- also lands '
      'in weak',
      () {
        final ranking = rankPatterns([
          buildPattern(id: 'p1', direction: PatternDirection.none, lift: 1.1),
        ]);

        expect(ranking.confirmed, isEmpty);
        expect(ranking.weak.map((p) => p.id), ['p1']);
      },
    );

    test(
      'a neutral-valence pattern (P0-2) -- badge-less for a different reason '
      '-- lands in weak too, since the ranking reads the one badge signal '
      'and never re-derives why it is null',
      () {
        final ranking = rankPatterns([
          buildPattern(id: 'p1', direction: PatternDirection.none, lift: 9.0),
        ]);

        expect(ranking.confirmed, isEmpty);
        expect(ranking.weak.map((p) => p.id), ['p1']);
      },
    );

    test('a keep or change pattern lands in confirmed', () {
      final ranking = rankPatterns([
        buildPattern(id: 'p1', direction: PatternDirection.keep, lift: 2.0),
        buildPattern(id: 'p2', direction: PatternDirection.change, lift: 3.0),
      ]);

      expect(ranking.confirmed.map((p) => p.id), ['p2', 'p1']);
      expect(ranking.weak, isEmpty);
    });

    test('confirmed patterns sort by lift, richest first', () {
      final ranking = rankPatterns([
        buildPattern(id: 'low', direction: PatternDirection.keep, lift: 1.6),
        buildPattern(id: 'high', direction: PatternDirection.keep, lift: 5.0),
        buildPattern(id: 'mid', direction: PatternDirection.keep, lift: 2.4),
      ]);

      expect(ranking.confirmed.map((p) => p.id), ['high', 'mid', 'low']);
    });

    test(
      'a historical pattern -- no recent occurrences -- sorts behind an '
      'equally strong active one, never ahead of it',
      () {
        final ranking = rankPatterns([
          buildPattern(
            id: 'historical',
            direction: PatternDirection.keep,
            status: PatternStatus.historical,
            lift: 5.0,
          ),
          buildPattern(
            id: 'active',
            direction: PatternDirection.keep,
            status: PatternStatus.active,
            lift: 5.0,
          ),
        ]);

        expect(ranking.confirmed.map((p) => p.id), ['active', 'historical']);
      },
    );

    test(
      'a historical pattern stays in the confirmed tier rather than falling '
      'to weak -- its lift is still real, only its recency changed',
      () {
        final ranking = rankPatterns([
          buildPattern(
            id: 'historical',
            direction: PatternDirection.keep,
            status: PatternStatus.historical,
            lift: 5.0,
          ),
          buildPattern(
            id: 'weak',
            direction: PatternDirection.none,
            lift: null,
          ),
        ]);

        expect(ranking.confirmed.map((p) => p.id), ['historical']);
        expect(ranking.weak.map((p) => p.id), ['weak']);
      },
    );

    test('ties in strength keep the patterns\' own relative order', () {
      final ranking = rankPatterns([
        buildPattern(id: 'first', direction: PatternDirection.keep, lift: 2.0),
        buildPattern(id: 'second', direction: PatternDirection.keep, lift: 2.0),
      ]);

      expect(ranking.confirmed.map((p) => p.id), ['first', 'second']);
    });

    test('weak patterns keep their original relative order -- there is no '
        'further authority to rank two badge-less patterns against each '
        'other', () {
      final ranking = rankPatterns([
        buildPattern(id: 'b', direction: PatternDirection.none, lift: null),
        buildPattern(id: 'a', direction: PatternDirection.none, lift: 8.0),
      ]);

      expect(ranking.weak.map((p) => p.id), ['b', 'a']);
    });

    test('an empty list ranks to two empty lists', () {
      final ranking = rankPatterns(const []);

      expect(ranking.confirmed, isEmpty);
      expect(ranking.weak, isEmpty);
    });
  });
}
