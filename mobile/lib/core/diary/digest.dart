import '../network/api_client.dart';
import 'calendar_date.dart';
import 'feeling.dart';
import 'pattern.dart';

/// Which way a movement figure moved, week over week (R-2).
///
/// A closed vocabulary, decided by the backend from the two raw counts it
/// also sends — this client never compares [DigestMovement.currentCount] and
/// [DigestMovement.previousCount] itself to reconstruct it, the same rule
/// [PatternDirection] follows for a pattern's badge.
enum DigestMovementDirection {
  /// More entries carried the feeling this week than last week.
  up,

  /// Fewer entries carried the feeling this week than last week.
  down,

  /// The same number of entries carried the feeling both weeks.
  flat;

  /// `'up'`/`'down'` map to their namesakes; anything else, including an
  /// unrecognised value, maps to [flat] — the safest reading of "we don't
  /// know which way this moved" is "say it didn't."
  static DigestMovementDirection fromWire(String raw) => switch (raw) {
    'up' => DigestMovementDirection.up,
    'down' => DigestMovementDirection.down,
    _ => DigestMovementDirection.flat,
  };
}

/// R-2's "one pattern": the strongest active pattern with evidence in the
/// digested week.
///
/// [sentence] arrives fully composed — see `digestHighlightSentenceFor` in
/// `backend/src/insights/analysis.ts` — and is rendered verbatim, the same
/// backend-owns-the-wording rule [Recommendation.sentence] follows.
class const DigestHighlight(
  /// The owning [Pattern.id] on `GET /insights` -- the digest sheet's link
  /// into Insights resolves this pattern's card there, never a second
  /// lookup.
  final String patternRef,
  final PatternKind kind,
  final String topic,
  final Feeling? feeling,

  /// Entries *this week* carrying this pattern's evidence -- not the
  /// pattern's own windowed [Pattern.occurrenceCount] on `GET /insights`,
  /// which counts the last `recency_window_days`, not a calendar week.
  final int weekCount,
  final double lift,
  final String sentence,
);

/// R-2's "one movement": an honest week-over-week delta for the highlighted
/// pattern's feeling — never a bare percentage or an unstated "more/less"
/// (see `movementSentenceFor` in `backend/src/insights/analysis.ts`).
///
/// Counts **feelings**, not topic×feeling pairs — an entry counts here the
/// moment it carries [feeling] as a confirmed feeling, regardless of which
/// topic it does or doesn't mention or how that pairing was confirmed. See
/// the backend doc comment above for why that is the honest choice rather
/// than an oversight.
class const DigestMovement(
  final Feeling? feeling,
  final int currentCount,
  final int previousCount,
  final DigestMovementDirection direction,
  final String sentence,
);

/// `GET /insights/digest`'s whole response (R-2): one pattern, one
/// recommendation, one movement figure, for the digest sheet a weekly
/// notification tap opens.
///
/// [highlight], [recommendation] and [movement] are independently absent —
/// each `null` means exactly "the backend had nothing honest to say for this
/// part this week," never an error partway through decoding the other two.
/// A screen renders whichever parts are present and says nothing about the
/// ones that are not, the same "absent parts omitted" rule the backend
/// itself follows.
class const Digest(
  /// `true` when nothing was written in the digested week at all -- see the
  /// backend's own doc comment on `DigestEmptyOut`. Every field below is at
  /// its inert default when this is `true`; a screen should check this
  /// first; and the acceptance criterion 1's determinism means fetching the
  /// same week twice always answers the same regardless of when it's asked.
  final bool empty,
  final int entryCount,

  /// The Monday that starts the digested week, or `null` on the empty shape
  /// (`week` is not sent then).
  final CalendarDate? week,
  final DigestHighlight? highlight,
  final Recommendation? recommendation,
  final DigestMovement? movement,
);

double? _toDouble(Object? value) => (value as num?)?.toDouble();

/// Decodes one digest highlight, or `null` when the field is absent or not
/// an object -- both read as "no pattern qualified this week," never as an
/// error.
DigestHighlight? digestHighlightFromJson(Object? json, FeelingCatalog catalog) {
  if (json is! JsonObject) return null;
  return DigestHighlight(
    json['pattern_ref'] as String? ?? '',
    PatternKind.fromWire(json['kind'] as String? ?? 'forward'),
    json['topic'] as String? ?? '',
    catalog.fromKey(json['feeling'] as String?),
    json['week_count'] as int? ?? 0,
    _toDouble(json['lift']) ?? 0.0,
    json['sentence'] as String? ?? '',
  );
}

/// Decodes one digest movement figure, or `null` when the field is absent or
/// not an object.
DigestMovement? digestMovementFromJson(Object? json, FeelingCatalog catalog) {
  if (json is! JsonObject) return null;
  return DigestMovement(
    catalog.fromKey(json['feeling'] as String?),
    json['current_count'] as int? ?? 0,
    json['previous_count'] as int? ?? 0,
    DigestMovementDirection.fromWire(json['direction'] as String? ?? 'flat'),
    json['sentence'] as String? ?? '',
  );
}

/// Decodes `GET /insights/digest`'s whole response.
///
/// `empty` defaults to `true` when absent, the same conservative direction
/// [Digest.empty]'s own doc comment explains: a field this client cannot
/// read is exactly the situation in which "nothing to show" is the honest
/// thing to render, never a fabricated highlight.
Digest digestFromJson(JsonObject json, FeelingCatalog catalog) {
  final empty = json['empty'] as bool? ?? true;
  if (empty) {
    return Digest(
      true,
      json['entry_count'] as int? ?? 0,
      null,
      null,
      null,
      null,
    );
  }
  return Digest(
    false,
    json['entry_count'] as int? ?? 0,
    CalendarDate.tryParse(json['week'] as String?),
    digestHighlightFromJson(json['highlight'], catalog),
    recommendationFromJson(json['recommendation']),
    digestMovementFromJson(json['movement'], catalog),
  );
}
