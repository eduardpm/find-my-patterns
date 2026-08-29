import '../network/api_client.dart';
import 'calendar_date.dart';
import 'entry.dart';
import 'feeling.dart';

/// Whether the badge tied to a pattern is to change the habit, keep it, or
/// say nothing (P0-2).
///
/// The backend derives this once from the pattern's kind and its feeling's
/// valence -- see `badgeDirectionFor` in `backend/src/insights/patterns.service.ts`,
/// the single function that decides it -- and this client renders whatever
/// it says, never re-deriving it from `kind` or the feeling here. [none] is
/// a neutral-valence feeling: no positive signal to reinforce and no
/// negative one to discourage, so there is nothing to advise.
enum PatternDirection {
  /// The pattern is worth keeping as-is.
  keep,

  /// The pattern is worth changing.
  change,

  /// The feeling behind this pattern is neutral. Neither badge applies.
  none;

  /// `'change'` and `'none'` map to their namesakes; anything else,
  /// including an unrecognised value, maps to [keep] -- the same
  /// forward-compatible default this had before [none] existed.
  static PatternDirection fromWire(String raw) => switch (raw) {
    'change' => PatternDirection.change,
    'none' => PatternDirection.none,
    _ => PatternDirection.keep,
  };
}

/// Which side of the comparison a pattern is about.
///
/// [forward] is the original claim: the feeling went *with* the topic.
/// [inverse] is the other half of the same 2x2 table — the feeling went
/// with the topic's *absence* — and it is what gives the app a "do more of
/// this" surface rather than only a list of things to cut down on.
enum PatternKind {
  /// The feeling went with the topic being present.
  forward,

  /// The feeling went with the topic being absent.
  inverse;

  /// `'inverse'` maps to [inverse]; anything else maps to [forward].
  static PatternKind fromWire(String raw) =>
      raw == 'inverse' ? PatternKind.inverse : PatternKind.forward;
}

/// Whether the evidence is inside the recency window or behind it.
///
/// A historical pattern is not a deleted one. It held often enough to count
/// once, and it stays on screen clearly marked, because a pattern the user
/// read and acted on vanishing between two visits is indistinguishable from
/// the app having been wrong.
enum PatternStatus {
  /// The pattern still holds within the recency window.
  active,

  /// The pattern held once but has aged out of the recency window.
  historical;

  /// `'historical'` maps to [historical]; anything else maps to [active].
  static PatternStatus fromWire(String raw) =>
      raw == 'historical' ? PatternStatus.historical : PatternStatus.active;
}

/// Why a pattern stopped qualifying. A fixed set, decided by data and never
/// by a model.
///
/// [belowLift] and [belowThreshold] are deliberately separate: one means
/// the evidence thinned out, the other means the evidence held and the
/// *association* weakened. They call for different words, and this client
/// can only tell them apart because the code does.
///
/// [excludedUnpaired] (#109, E-1d) is a fifth, separate from
/// [noLongerConfirmed] for the same reason: the entries behind it carry a
/// feeling the user confirmed, just never paired with this exact topic.
/// Folding it into [noLongerConfirmed] is the bug #109 fixes -- that reason
/// claims no confirmed feeling exists at all, which is false of these
/// entries.
///
/// An unrecognised value falls back to [belowThreshold] rather than
/// crashing, so a reason the backend gains after this build shipped still
/// renders as a withdrawal.
enum WithdrawalReason {
  /// The occurrence count dropped below the minimum.
  belowThreshold,

  /// The evidence held, but the association weakened below the minimum
  /// lift.
  belowLift,

  /// The feeling behind the pattern is no longer a confirmed one.
  noLongerConfirmed,

  /// The topic behind the pattern was merged into another.
  topicMerged,

  /// The entries carry a confirmed feeling, but never a confirmed pairing
  /// of it with this topic -- #26's mixed-valence pairing rule excluded
  /// them from this pair's count (#109, E-1d).
  excludedUnpaired;

  /// Resolves a wire withdrawal-reason string; anything unrecognised,
  /// including null, falls back to [belowThreshold]. Never throws.
  static WithdrawalReason fromWire(String raw) => switch (raw) {
    'below_lift' => WithdrawalReason.belowLift,
    'no_longer_confirmed' => WithdrawalReason.noLongerConfirmed,
    'topic_merged' => WithdrawalReason.topicMerged,
    'excluded_unpaired' => WithdrawalReason.excludedUnpaired,
    _ => WithdrawalReason.belowThreshold,
  };
}

/// One entry standing behind a pattern.
///
/// Rendered exactly as received. This client does not re-derive the trail,
/// does not filter it, and does not sort it — the backend guarantees it is
/// ordered oldest first and that its length equals the pattern's occurrence
/// count, and re-deciding either here is how the two clients start
/// disagreeing about the same diary.
class const PatternEvidence(
  final String entryId,
  final CalendarDate entryDate,
  final String rawText,
  final List<Feeling> feelings,
  final FeelingSource feelingSource,
);

/// Another topic this one keeps company with, and the split that shows it.
class const Confounder(
  final String topic,
  final double coOccurrenceRate,
  final int bothCount,
  final int onlyThisCount,
  final int onlyOtherCount,
  final int neitherCount,

  /// True when no entry in the diary separates the two, so nothing can be
  /// concluded.
  final bool inseparable,
  final String note,
);

/// R-1: a "Worth trying" card, attached to the pattern it was derived from.
///
/// [headline] and [sentence] arrive fully composed from the backend and are
/// rendered verbatim -- see `RecommendationOut` in
/// `backend/src/insights/patterns.service.ts`. This client does not turn
/// [actionTopic] back into prose; that is exactly the re-deriving
/// `mobile/CLAUDE.md`'s "the backend owns the logic" forbids, the same rule
/// every other field on [Pattern] already follows.
class const Recommendation(
  final String actionTopic,
  final String headline,
  final String sentence,

  /// The owning [Pattern.id] -- not a second identifier to reconcile, just
  /// the key of the card already in [InsightsResult.patterns] this one
  /// points back at.
  final String patternRef,
);

/// A detected, threshold-confirmed topic-feeling correlation from
/// `GET /insights`.
class const Pattern(
  final String id,
  final PatternKind kind,
  final String topic,
  final Feeling? feeling,

  /// The windowed count — and, by construction, the size of [evidence].
  final int occurrenceCount,
  final int lifetimeCount,
  final PatternStatus status,
  final PatternDirection direction,
  final String narrativeText,
  final String suggestionText,
  final int presentCount,
  final int presentTotal,
  final int absentCount,
  final int absentTotal,
  final double? presentRate,
  final double? absentRate,
  final double baseRate,

  /// How much likelier the feeling is with the topic than without — or
  /// null, with a reason.
  final double? lift,
  final String? comparisonReason,
  final String? comparisonNote,
  final bool isStrong,
  final CalendarDate? lastOccurrenceDate,
  final int? daysSinceLastOccurrence,
  final String? historicalNote,
  final List<Confounder> confounders,
  final List<PatternEvidence> evidence,
  final DateTime lastUpdatedAt,

  /// R-1: `null` for almost every pattern -- only the handful whose own
  /// [direction] already reads [PatternDirection.keep] carry one. Absent
  /// entirely on a backend that predates this field, which decodes the same
  /// way as "this pattern did not qualify" (`recommendationFromJson`'s null
  /// default, the same inert-default convention every field here follows).
  final Recommendation? recommendation,
);

/// A pattern that went away, and the numbers that say why.
class const Withdrawal(
  final String id,
  final String topic,
  final String feeling,
  final PatternKind kind,
  final int previousCount,
  final int newCount,
  final WithdrawalReason reason,
  final String detailText,
  final DateTime withdrawnAt,

  /// Whether this notice has appeared since the user last acknowledged
  /// them.
  final bool isNew,
);

/// Every threshold the engine applied, served with the answer.
///
/// Read, never assumed: this client saying "in the last 30 days" reads the
/// 30 from here rather than from a constant of its own.
class const EngineConstants(
  final int minOccurrenceThreshold,
  final int recencyWindowDays,
  final double minLift,
  final double strongLift,
  final int strongMinOccurrences,
  final int minComparisonEntries,
  final double collinearityThreshold,
  final int minBucketEntries,
  final int minIntensity,
  final int maxIntensity,
) {
  /// Used only before the first response lands, so a screen can lay itself
  /// out without branching on null. Every value is overwritten by the
  /// backend's own on the first read; none of them is ever shown as a fact
  /// on its own.
  static const EngineConstants placeholder = EngineConstants(
    3,
    30,
    1.5,
    3.0,
    5,
    3,
    0.8,
    3,
    1,
    5,
  );
}

/// Wraps `GET /insights`' response, including the "not enough data yet"
/// empty state.
class const InsightsResult(
  final List<Pattern> patterns,
  final List<Withdrawal> withdrawals,
  final int newWithdrawalCount,
  final bool insufficientData,
  final EngineConstants constants,
);

/// One weekday or time-of-day bucket in the "when" view.
class const WhenBucket(
  final String key,
  final String label,
  final int entryCount,

  /// Mean valence on the -1 .. +1 scale, or null when the bucket is too
  /// thin to average.
  final double? averageValence,
  final double? negativeRate,
  final bool sufficient,
);

/// The time-of-day breakdown behind the Insights "when" panel.
class const WhenInsights(
  final int windowDays,
  final int minBucketEntries,
  final int totalEntries,
  final List<WhenBucket> weekdays,
  final List<WhenBucket> timesOfDay,
  final String? bestWeekday,
  final String? worstWeekday,
  final String? bestTimeOfDay,
  final String? worstTimeOfDay,

  /// CH-5: mean valence and entry count per 2-hour block (`00:00-02:00` …
  /// `22:00-00:00`), for the heat strip under "By time of day". The same
  /// [WhenBucket] shape and the same [minBucketEntries] suppression rule as
  /// [weekdays] and [timesOfDay] -- an empty list, not an error, is what an
  /// older backend that predates this field decodes to.
  final List<WhenBucket> hourly,
  final String? bestHour,
  final String? worstHour,

  /// The [timesOfDay] bucket the diary writes into most, by entry count --
  /// null on a tie or an empty window. A separate field from
  /// [bestTimeOfDay]/[worstTimeOfDay], which rank by valence, not by how
  /// many entries a period holds.
  final String? busiestTimeOfDay,
);

/// What the diary already says about the topics in an entry that has just
/// been saved.
class const PatternEcho(
  final String patternId,
  final String topic,
  final String feeling,
  final int occurrenceCount,
  final int presentCount,
  final int presentTotal,
  final double? lift,
  final String narrativeText,
);

double? _toDouble(Object? value) => (value as num?)?.toDouble();

/// Matches a trailing `Z` or a numeric UTC offset such as `+02:00`.
final RegExp _zonePattern = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

/// Parses a backend timestamp into a UTC instant. See the twin of this
/// function in `entry.dart` for why an unmarked string is given an explicit
/// `Z` before parsing rather than being handed straight to [DateTime.parse].
DateTime _parseInstant(String raw) {
  try {
    final normalized = _zonePattern.hasMatch(raw) ? raw : '${raw}Z';
    return DateTime.parse(normalized).toUtc();
  } on FormatException {
    return DateTime.utc(1970);
  }
}

/// Decodes one evidence entry, resolving its feelings through [catalog].
PatternEvidence patternEvidenceFromJson(
  JsonObject json,
  FeelingCatalog catalog,
) => PatternEvidence(
  json['entry_id']! as String,
  CalendarDate.parse(json['entry_date']! as String),
  json['raw_text']! as String,
  catalog.fromKeys(
    (json['feeling_keys'] as List<Object?>?)?.cast<String>() ?? const [],
  ),
  FeelingSource.fromWire(json['feeling_source'] as String? ?? 'confirmed'),
);

/// Decodes one confounder. Every numeric, boolean, and string field defaults
/// to its inert value (0, 0.0, false, `''`) so a backend that predates a
/// field parses as "nothing here" rather than failing.
Confounder confounderFromJson(JsonObject json) => Confounder(
  json['topic']! as String,
  _toDouble(json['co_occurrence_rate']) ?? 0.0,
  json['both_count'] as int? ?? 0,
  json['only_this_count'] as int? ?? 0,
  json['only_other_count'] as int? ?? 0,
  json['neither_count'] as int? ?? 0,
  json['inseparable'] as bool? ?? false,
  json['note'] as String? ?? '',
);

/// Decodes one recommendation, or `null` when the field itself is absent or
/// not an object -- both read as "this pattern did not qualify", never as an
/// error, since an older backend and a pattern the engine did not promote
/// are indistinguishable at the wire.
Recommendation? recommendationFromJson(Object? json) {
  if (json is! JsonObject) return null;
  return Recommendation(
    json['action_topic'] as String? ?? '',
    json['headline'] as String? ?? '',
    json['sentence'] as String? ?? '',
    json['pattern_ref'] as String? ?? '',
  );
}

/// Decodes one pattern.
///
/// Every field the roadmap added carries a default, and the default is the
/// inert value — no lift, no confounders, no evidence, `active` — because a
/// missing field means "this backend does not compute that", never "zero".
Pattern patternFromJson(JsonObject json, FeelingCatalog catalog) => Pattern(
  json['id']! as String,
  PatternKind.fromWire(json['kind'] as String? ?? 'forward'),
  json['topic']! as String,
  catalog.fromKey(json['feeling'] as String?),
  json['occurrence_count']! as int,
  json['lifetime_count'] as int? ?? 0,
  PatternStatus.fromWire(json['status'] as String? ?? 'active'),
  PatternDirection.fromWire(json['direction'] as String? ?? 'keep'),
  json['narrative_text']! as String,
  json['suggestion_text']! as String,
  json['present_count'] as int? ?? 0,
  json['present_total'] as int? ?? 0,
  json['absent_count'] as int? ?? 0,
  json['absent_total'] as int? ?? 0,
  _toDouble(json['present_rate']),
  _toDouble(json['absent_rate']),
  _toDouble(json['base_rate']) ?? 0.0,
  _toDouble(json['lift']),
  json['comparison_reason'] as String?,
  json['comparison_note'] as String?,
  json['is_strong'] as bool? ?? false,
  CalendarDate.tryParse(json['last_occurrence_date'] as String?),
  json['days_since_last_occurrence'] as int?,
  json['historical_note'] as String?,
  [
    for (final dto
        in (json['confounders'] as List<Object?>?)?.cast<JsonObject>() ??
            const <JsonObject>[])
      confounderFromJson(dto),
  ],
  [
    for (final dto
        in (json['evidence'] as List<Object?>?)?.cast<JsonObject>() ??
            const <JsonObject>[])
      patternEvidenceFromJson(dto, catalog),
  ],
  _parseInstant(json['last_updated_at']! as String),
  recommendationFromJson(json['recommendation']),
);

/// Decodes one withdrawal.
Withdrawal withdrawalFromJson(JsonObject json) => Withdrawal(
  json['id']! as String,
  json['topic']! as String,
  json['feeling']! as String,
  PatternKind.fromWire(json['kind'] as String? ?? 'forward'),
  json['previous_count'] as int? ?? 0,
  json['new_count'] as int? ?? 0,
  WithdrawalReason.fromWire(json['reason'] as String? ?? 'below_threshold'),
  json['detail_text'] as String? ?? '',
  _parseInstant(json['withdrawn_at']! as String),
  json['is_new'] as bool? ?? false,
);

/// Decodes the engine's constants, defaulting every field to
/// [EngineConstants.placeholder]'s value.
EngineConstants engineConstantsFromJson(JsonObject json) => EngineConstants(
  json['min_occurrence_threshold'] as int? ?? 3,
  json['recency_window_days'] as int? ?? 30,
  _toDouble(json['min_lift']) ?? 1.5,
  _toDouble(json['strong_lift']) ?? 3.0,
  json['strong_min_occurrences'] as int? ?? 5,
  json['min_comparison_entries'] as int? ?? 3,
  _toDouble(json['collinearity_threshold']) ?? 0.8,
  json['min_bucket_entries'] as int? ?? 3,
  json['min_intensity'] as int? ?? 1,
  json['max_intensity'] as int? ?? 5,
);

/// Decodes `GET /insights`'s whole response.
InsightsResult insightsResultFromJson(
  JsonObject json,
  FeelingCatalog catalog,
) => InsightsResult(
  [
    for (final dto
        in (json['patterns'] as List<Object?>?)?.cast<JsonObject>() ??
            const <JsonObject>[])
      patternFromJson(dto, catalog),
  ],
  [
    for (final dto
        in (json['withdrawals'] as List<Object?>?)?.cast<JsonObject>() ??
            const <JsonObject>[])
      withdrawalFromJson(dto),
  ],
  json['new_withdrawal_count'] as int? ?? 0,
  json['insufficient_data'] as bool? ?? false,
  engineConstantsFromJson(
    (json['constants'] as JsonObject?) ?? const <String, Object?>{},
  ),
);

/// Decodes one weekday or time-of-day bucket.
WhenBucket whenBucketFromJson(JsonObject json) => WhenBucket(
  json['key']! as String,
  json['label']! as String,
  json['entry_count'] as int? ?? 0,
  _toDouble(json['average_valence']),
  _toDouble(json['negative_rate']),
  json['sufficient'] as bool? ?? false,
);

/// Decodes `GET /insights/when`'s whole response.
WhenInsights whenInsightsFromJson(JsonObject json) => WhenInsights(
  json['window_days'] as int? ?? 30,
  json['min_bucket_entries'] as int? ?? 3,
  json['total_entries'] as int? ?? 0,
  [
    for (final dto
        in (json['weekdays'] as List<Object?>?)?.cast<JsonObject>() ??
            const <JsonObject>[])
      whenBucketFromJson(dto),
  ],
  [
    for (final dto
        in (json['times_of_day'] as List<Object?>?)?.cast<JsonObject>() ??
            const <JsonObject>[])
      whenBucketFromJson(dto),
  ],
  json['best_weekday'] as String?,
  json['worst_weekday'] as String?,
  json['best_time_of_day'] as String?,
  json['worst_time_of_day'] as String?,
  [
    for (final dto
        in (json['hourly'] as List<Object?>?)?.cast<JsonObject>() ??
            const <JsonObject>[])
      whenBucketFromJson(dto),
  ],
  json['best_hour'] as String?,
  json['worst_hour'] as String?,
  json['busiest_time_of_day'] as String?,
);

/// Decodes one echoed pattern. The numbers are the pattern card's own;
/// nothing here is recomputed.
PatternEcho patternEchoFromJson(JsonObject json) => PatternEcho(
  json['pattern_id']! as String,
  json['topic']! as String,
  json['feeling']! as String,
  json['occurrence_count'] as int? ?? 0,
  json['present_count'] as int? ?? 0,
  json['present_total'] as int? ?? 0,
  _toDouble(json['lift']),
  json['narrative_text'] as String? ?? '',
);
