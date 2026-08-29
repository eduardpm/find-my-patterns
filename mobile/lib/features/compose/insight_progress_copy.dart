import '../../core/diary/pattern.dart';

/// The insight progress surface's copy (#37, L-2) — counts only, no
/// prediction, no advice, per §11.6 rung 2. Every number here is read off
/// [InsightProgress], never invented or re-derived; this file only chooses
/// the words and the pluralisation around numbers the backend already
/// decided.

/// "Tracking 7 topics across 12 entries." — the cold-start counting line,
/// singular/plural on both nouns independently (a diary can easily be at
/// "1 topic across 12 entries" or "7 topics across 1 entry").
String insightProgressTrackingLine(InsightProgress progress) {
  final topicWord = progress.topicsTracked == 1 ? 'topic' : 'topics';
  final entryWord = progress.confirmedEntries == 1 ? 'entry' : 'entries';
  return 'Tracking ${progress.topicsTracked} $topicWord across '
      '${progress.confirmedEntries} $entryWord.';
}

/// The "Closest to a pattern" line, split into its three pieces so the
/// caller can render the middle `pair` piece in its own style (bold, in the
/// shipped panel) without this file making any presentation decision of
/// its own.
///
/// `null` when [InsightProgress.pairs] is empty — the ordinary case for an
/// entry that moved nothing close to a pattern, not a failure.
///
/// Only ever the first, nearest-to-threshold pair: the issue's own example
/// copy states a single pair ("Closest to a pattern", singular), and
/// `ProgressOut.pairs` carrying up to two is the backend's own headroom and
/// determinism guarantee, not an instruction to print two lines.
typedef ClosestPairLine = ({String prefix, String pair, String suffix});

ClosestPairLine? insightProgressClosestPairLine(InsightProgress progress) {
  if (progress.pairs.isEmpty) return null;
  final nearest = progress.pairs.first;
  // Pluralised on the threshold (the total), not the occurrence count --
  // the same agreement `forwardNarrative` in `backend/src/insights/analysis.ts`
  // uses for its own "N of M entries" ("You felt calm in 1 of 12 entries
  // mentioning walking" stays plural on 12, not singular on 1). Both
  // numbers here count the same unit (occurrences of this pair), so the
  // noun describing that unit takes its number from the total the reader
  // is comparing against, exactly as that established phrasing does.
  final noun = nearest.threshold == 1 ? 'occurrence' : 'occurrences';
  return (
    prefix: 'Closest to a pattern: ',
    pair: '${nearest.topic} + ${nearest.feeling}',
    suffix: ' — ${nearest.occurrences} of ${nearest.threshold} $noun.',
  );
}
