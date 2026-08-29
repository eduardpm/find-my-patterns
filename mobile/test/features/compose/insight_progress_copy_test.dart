import 'package:find_my_patterns/core/diary/pattern.dart';
import 'package:find_my_patterns/features/compose/insight_progress_copy.dart';
import 'package:flutter_test/flutter_test.dart';

InsightProgress _progress({
  int topicsTracked = 7,
  int confirmedEntries = 12,
  List<ProgressPair> pairs = const [],
  int surfacedPatternCount = 0,
  int surfacedPatternGate = 3,
}) => InsightProgress(
  topicsTracked,
  confirmedEntries,
  pairs,
  surfacedPatternCount,
  surfacedPatternGate,
);

void main() {
  group('insightProgressTrackingLine', () {
    test('matches the issue\'s own example exactly', () {
      expect(
        insightProgressTrackingLine(
          _progress(topicsTracked: 7, confirmedEntries: 12),
        ),
        'Tracking 7 topics across 12 entries.',
      );
    });

    test('singular "topic" for exactly one topic', () {
      expect(
        insightProgressTrackingLine(
          _progress(topicsTracked: 1, confirmedEntries: 12),
        ),
        'Tracking 1 topic across 12 entries.',
      );
    });

    test('singular "entry" for exactly one confirmed entry', () {
      expect(
        insightProgressTrackingLine(
          _progress(topicsTracked: 7, confirmedEntries: 1),
        ),
        'Tracking 7 topics across 1 entry.',
      );
    });

    test('both singular at once -- the two nouns pluralise independently', () {
      expect(
        insightProgressTrackingLine(
          _progress(topicsTracked: 1, confirmedEntries: 1),
        ),
        'Tracking 1 topic across 1 entry.',
      );
    });
  });

  group('insightProgressClosestPairLine', () {
    test('returns null when there is no near-threshold pair', () {
      expect(
        insightProgressClosestPairLine(_progress(pairs: const [])),
        isNull,
      );
    });

    test('matches the issue\'s own example exactly, split at the pair', () {
      final line = insightProgressClosestPairLine(
        _progress(
          pairs: const [ProgressPair('work', 'anxious', 2, 3)],
        ),
      );
      expect(line, isNotNull);
      expect(line!.prefix, 'Closest to a pattern: ');
      expect(line.pair, 'work + anxious');
      expect(line.suffix, ' — 2 of 3 occurrences.');
      expect(
        '${line.prefix}${line.pair}${line.suffix}',
        'Closest to a pattern: work + anxious — 2 of 3 occurrences.',
      );
    });

    test(
      'stays plural on "occurrences" for a single occurrence -- '
      'agreement follows the threshold, not the occurrence count',
      () {
        final line = insightProgressClosestPairLine(
          _progress(
            pairs: const [ProgressPair('coffee', 'calm', 1, 3)],
          ),
        );
        expect(line!.suffix, ' — 1 of 3 occurrences.');
      },
    );

    test('singular "occurrence" only when the threshold itself is one', () {
      final line = insightProgressClosestPairLine(
        _progress(
          pairs: const [ProgressPair('coffee', 'calm', 1, 1)],
        ),
      );
      expect(line!.suffix, ' — 1 of 1 occurrence.');
    });

    test('reads the threshold from the pair, never a hardcoded 3', () {
      final line = insightProgressClosestPairLine(
        _progress(
          pairs: const [ProgressPair('sleep', 'tired', 4, 5)],
        ),
      );
      expect(line!.suffix, ' — 4 of 5 occurrences.');
    });

    test('only the first (nearest-to-threshold) pair is ever rendered', () {
      final line = insightProgressClosestPairLine(
        _progress(
          pairs: const [
            ProgressPair('work', 'anxious', 2, 3),
            ProgressPair('family', 'happy', 1, 3),
          ],
        ),
      );
      expect(line!.pair, 'work + anxious');
    });
  });
}
