import '../../core/diary/pattern.dart';
import 'pattern_card.dart';

/// The two tiers [rankPatterns] splits a pattern list into for the Insights
/// feed (UX-2).
///
/// [confirmed] gets full billing, sorted strongest first. [weak] is set
/// aside, undecorated, for the caller to render collapsed under a "Weaker
/// signals" header, expandable to the full card on tap.
class const PatternRanking(
  final List<Pattern> confirmed,
  final List<Pattern> weak,
);

/// Splits and orders [patterns] for the Insights feed (UX-2).
///
/// A pattern lands in [PatternRanking.confirmed] exactly when
/// [patternBadgeFor] gives it a badge. The backend's own `badgeDirectionFor`
/// (P0-6, `backend/src/insights/patterns.service.ts`) has already decided
/// that: a badge means the pattern's lift is both defined and at least
/// `EngineConstants.minLift`, and this function reads that decision through
/// the one function that makes it rather than re-deriving it from
/// [Pattern.lift] here.
///
/// Everything else lands in [PatternRanking.weak] -- an undefined lift, one
/// below the minimum, or a neutral-valence feeling with no signal to advise
/// on either way (P0-2). All three collapse to the same `none` badge, and
/// this function does not tell them apart: that would be a second signal
/// invented on top of the one the backend already computed.
/// [PatternRanking.weak] keeps [patterns]' own relative order -- there is
/// no further authority to rank two badge-less patterns against each
/// other.
///
/// [PatternRanking.confirmed] is ordered by `lift × has-recent-occurrences`,
/// richest first -- a pattern still holding inside the recency window
/// ([PatternStatus.active]) outranks an equally strong one that has aged out
/// of it ([PatternStatus.historical]). A historical pattern's lift is no
/// less real for being older, which is why it stays in the confirmed tier
/// rather than falling to the weak one; it simply sorts behind whatever is
/// still happening. Ties keep [patterns]' own relative order.
///
/// A pure function on purpose -- UX-2's own acceptance criterion: no
/// `BuildContext`, no backend call, just a list in and two lists out, so the
/// ranking is unit-testable without a widget in sight.
PatternRanking rankPatterns(List<Pattern> patterns) {
  final confirmed = <Pattern>[];
  final weak = <Pattern>[];
  for (final pattern in patterns) {
    (patternBadgeFor(pattern) != null ? confirmed : weak).add(pattern);
  }
  final byStrengthThenOriginalOrder =
      [
        for (var index = 0; index < confirmed.length; index++) index,
      ]..sort((a, b) {
        final byStrength = _strength(
          confirmed[b],
        ).compareTo(_strength(confirmed[a]));
        return byStrength != 0 ? byStrength : a.compareTo(b);
      });
  return PatternRanking([
    for (final index in byStrengthThenOriginalOrder) confirmed[index],
  ], weak);
}

/// `lift × has-recent-occurrences`, the formula UX-2 asks for.
///
/// Only ever called on a pattern already sorted into [PatternRanking
/// .confirmed], where [patternBadgeFor]'s own contract guarantees
/// [Pattern.lift] is non-null -- the `?? 0` below is unreachable defensive
/// code, not a real fallback.
double _strength(Pattern pattern) =>
    (pattern.lift ?? 0) * (pattern.status == PatternStatus.active ? 1 : 0);
