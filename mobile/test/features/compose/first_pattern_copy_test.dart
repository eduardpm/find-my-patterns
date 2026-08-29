import 'package:find_my_patterns/core/diary/feeling.dart';
import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/features/compose/first_pattern_copy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'json_fixtures.dart';

/// Decodes a `patternJson(...)` fixture into a real [Pattern] -- this
/// suite only ever needs [Pattern.occurrenceCount], so an empty catalog is
/// enough to resolve the (unset) `feeling` field.
Pattern _pattern({required int occurrenceCount}) => patternFromJson(
  patternJson(occurrenceCount: occurrenceCount),
  FeelingCatalog.empty,
);

void main() {
  group('firstPatternNotificationBody', () {
    test('names the real occurrence count, e.g. the ticket\'s own example', () {
      expect(
        firstPatternNotificationBody(_pattern(occurrenceCount: 3)),
        '3 entries point the same way. See the evidence.',
      );
    });

    test('never hardcodes the count -- a different pattern shows a '
        'different number', () {
      expect(
        firstPatternNotificationBody(_pattern(occurrenceCount: 7)),
        '7 entries point the same way. See the evidence.',
      );
    });

    test('singular phrasing for exactly one occurrence', () {
      expect(
        firstPatternNotificationBody(_pattern(occurrenceCount: 1)),
        '1 entry points the same way. See the evidence.',
      );
    });

    test('falls back to copy naming no number when the count cannot be '
        'honestly shown', () {
      expect(
        firstPatternNotificationBody(_pattern(occurrenceCount: 0)),
        'The evidence is ready. See what the diary found.',
      );
    });
  });

  test('firstPatternNotificationTitle matches the ticket\'s copy exactly', () {
    expect(firstPatternNotificationTitle, 'Your first pattern is ready');
  });

  test('firstPatternCardText matches the ticket\'s copy exactly', () {
    expect(
      firstPatternCardText,
      'Your first pattern is ready — see the evidence.',
    );
  });
}
