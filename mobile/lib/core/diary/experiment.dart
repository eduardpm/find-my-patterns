import '../network/api_client.dart';
import 'calendar_date.dart';

/// Whether an experiment is testing more of a topic or less of it (R-3b).
///
/// Decided once, when the experiment is created, from the pattern it was
/// started against -- a `change`-badged pattern (the topic is worth cutting
/// back on) starts a [lessOf] experiment, a `keep`-badged one starts
/// [moreOf]. Once created, the wire value is what this client renders; it
/// is never re-derived from the pattern again.
enum HypothesisKind {
  /// Testing whether more of the topic changes the feeling.
  moreOf,

  /// Testing whether less of the topic changes the feeling.
  lessOf;

  /// `'less_of'` maps to [lessOf]; anything else, including an
  /// unrecognised value, maps to [moreOf].
  static HypothesisKind fromWire(String raw) =>
      raw == 'less_of' ? HypothesisKind.lessOf : HypothesisKind.moreOf;

  /// The wire value this client sends back on `POST /experiments`.
  String get wireValue => this == HypothesisKind.lessOf ? 'less_of' : 'more_of';
}

/// Where an experiment stands (R-3a).
///
/// [finished] is a fact the backend derives from the clock, not a state
/// this client ever sets directly -- an experiment simply stops being
/// [active] once `end_date` has passed, the next time anything reads it.
enum ExperimentStatus {
  /// Still running.
  active,

  /// Its window has closed; results are final.
  finished,

  /// Abandoned before its window closed.
  abandoned;

  /// `'finished'` and `'abandoned'` map to their namesakes; anything else,
  /// including an unrecognised value, maps to [active].
  static ExperimentStatus fromWire(String raw) => switch (raw) {
    'finished' => ExperimentStatus.finished,
    'abandoned' => ExperimentStatus.abandoned,
    _ => ExperimentStatus.active,
  };
}

/// The thresholds and defaults the experiments engine applies, served with
/// every experiments response (`backend/src/experiments/constants.ts`).
///
/// Read, never assumed: the length picker's 7–28 day range and its default
/// of 7 come from here, exactly like `EngineConstants` backs every number
/// on the Insights screen -- not from a literal this client keeps of its
/// own.
class const ExperimentConstants(
  final int defaultLengthDays,
  final int minLengthDays,
  final int maxLengthDays,
  final int minBucketEntries,
) {
  /// Used only before the first experiments response has ever landed --
  /// there is no dedicated "constants" endpoint, so a setup sheet opened
  /// before any experiment has ever been created has nothing real to read
  /// yet. Every value here happens to match the backend's own defaults
  /// (`experiments/constants.ts`) but is never shown as a fact on its own:
  /// the moment `POST /experiments`, `GET /experiments/active`, or an
  /// abandon or results call answers for real, its own `constants` replace
  /// this.
  static const ExperimentConstants placeholder = ExperimentConstants(
    7,
    7,
    28,
    3,
  );
}

/// Inclusive days between [a] and [b] -- negative when [b] is before [a].
int _daysBetween(CalendarDate a, CalendarDate b) =>
    b.toDateTime().difference(a.toDateTime()).inDays;

/// One N-of-1 experiment (R-3a/R-3b): a pattern under test, for a fixed
/// window.
class const Experiment(
  final String id,
  final String patternTopic,
  final String patternFeeling,
  final HypothesisKind hypothesisKind,
  final CalendarDate startDate,
  final CalendarDate endDate,
  final ExperimentStatus status,
  final DateTime createdAt,
  final ExperimentConstants constants,
) {
  /// The experiment's planned length, in days -- [endDate] inclusive.
  int get lengthDays => _daysBetween(startDate, endDate) + 1;

  /// Which day of the plan [today] falls on, for the "day 3 of 7" banner
  /// text -- 1-indexed and clamped to `1..lengthDays`: day 1 for a start
  /// date still ahead (an experiment created for a future date), the last
  /// day once [today] has reached or passed [endDate].
  int dayNumber(CalendarDate today) {
    final elapsed = _daysBetween(startDate, today) + 1;
    if (elapsed < 1) return 1;
    if (elapsed > lengthDays) return lengthDays;
    return elapsed;
  }

  /// Whether this experiment is the one currently testing [topic] and
  /// [feeling] -- what a pattern card checks to show "Experiment running"
  /// instead of "Test this pattern".
  bool matches({required String topic, required String? feeling}) =>
      patternTopic == topic && patternFeeling == feeling;
}

/// One window of an experiment's results -- the "during" window or the
/// "before" baseline, counted exactly the same way.
class const ExperimentWindow(
  final CalendarDate startDate,
  final CalendarDate endDate,
  final int totalDays,

  /// Distinct calendar days on which the topic was mentioned at least once.
  final int daysWithTopic,

  /// Entries mentioning the topic, with the feeling.
  final int presentCount,

  /// Entries mentioning the topic.
  final int presentTotal,

  /// Entries not mentioning the topic, with the feeling.
  final int absentCount,

  /// Entries not mentioning the topic.
  final int absentTotal,
  final double? presentRate,
  final double? absentRate,
);

/// `GET /experiments/{id}/results`' whole response: the two-window
/// comparison and the deterministic verdict.
class const ExperimentResults(
  final Experiment experiment,
  final ExperimentWindow experimentWindow,
  final ExperimentWindow baselineWindow,

  /// The verdict, stated in full by the backend -- rendered verbatim.
  /// Nothing here is reworded, summarised, or judged again on this client.
  final String verdictText,

  /// Whether either window's count fell below
  /// [ExperimentConstants.minBucketEntries] -- rendered with the same
  /// weight as a clear result, never smaller or greyed out. An honest "not
  /// enough data" is not a failure state.
  final bool insufficientData,
  final ExperimentConstants constants,
);

double? _toDouble(Object? value) => (value as num?)?.toDouble();

/// Matches a trailing `Z` or a numeric UTC offset such as `+02:00`. See the
/// twin of this pattern in `pattern.dart` and `entry.dart`.
final RegExp _zonePattern = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

DateTime _parseInstant(String raw) {
  try {
    final normalized = _zonePattern.hasMatch(raw) ? raw : '${raw}Z';
    return DateTime.parse(normalized).toUtc();
  } on FormatException {
    return DateTime.utc(1970);
  }
}

/// Decodes an experiment's `constants`, defaulting every field to
/// [ExperimentConstants.placeholder]'s value -- a backend that predates a
/// field, or a caller that never received one, still gets an inert scale.
ExperimentConstants experimentConstantsFromJson(JsonObject json) =>
    ExperimentConstants(
      json['default_length_days'] as int? ?? 7,
      json['min_length_days'] as int? ?? 7,
      json['max_length_days'] as int? ?? 28,
      json['min_bucket_entries'] as int? ?? 3,
    );

/// Decodes one experiment.
Experiment experimentFromJson(JsonObject json) => Experiment(
  json['id']! as String,
  json['pattern_topic']! as String,
  json['pattern_feeling']! as String,
  HypothesisKind.fromWire(json['hypothesis_kind'] as String? ?? 'more_of'),
  CalendarDate.parse(json['start_date']! as String),
  CalendarDate.parse(json['end_date']! as String),
  ExperimentStatus.fromWire(json['status'] as String? ?? 'active'),
  _parseInstant(json['created_at']! as String),
  experimentConstantsFromJson(
    (json['constants'] as JsonObject?) ?? const <String, Object?>{},
  ),
);

/// Decodes one results window (`experiment_window` or `baseline_window`).
ExperimentWindow experimentWindowFromJson(JsonObject json) => ExperimentWindow(
  CalendarDate.parse(json['start_date']! as String),
  CalendarDate.parse(json['end_date']! as String),
  json['total_days'] as int? ?? 0,
  json['days_with_topic'] as int? ?? 0,
  json['present_count'] as int? ?? 0,
  json['present_total'] as int? ?? 0,
  json['absent_count'] as int? ?? 0,
  json['absent_total'] as int? ?? 0,
  _toDouble(json['present_rate']),
  _toDouble(json['absent_rate']),
);

/// Decodes `GET /experiments/{id}/results`'s whole response.
ExperimentResults experimentResultsFromJson(JsonObject json) =>
    ExperimentResults(
      experimentFromJson(
        (json['experiment'] as JsonObject?) ?? const <String, Object?>{},
      ),
      experimentWindowFromJson(
        (json['experiment_window'] as JsonObject?) ?? const <String, Object?>{},
      ),
      experimentWindowFromJson(
        (json['baseline_window'] as JsonObject?) ?? const <String, Object?>{},
      ),
      json['verdict_text'] as String? ?? '',
      json['insufficient_data'] as bool? ?? false,
      experimentConstantsFromJson(
        (json['constants'] as JsonObject?) ?? const <String, Object?>{},
      ),
    );
