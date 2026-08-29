import '../network/api_client.dart';
import 'calendar_date.dart';
import 'feeling.dart';

/// Which flow produced the entry.
enum EntryMode {
  /// Written by answering the guided-question flow.
  guided,

  /// Written as free text.
  freeform;

  /// Resolves a wire mode string. `'guided'` is guided; everything else,
  /// including an unrecognised value, is freeform.
  static EntryMode fromWire(String raw) =>
      raw == 'guided' ? EntryMode.guided : EntryMode.freeform;
}

/// Tracks the hybrid suggest/confirm flow for an entry's feelings.
enum FeelingSource {
  /// The analyser proposed this feeling; nobody has acted on it yet.
  suggested,

  /// The user picked this feeling, matching or not matching a suggestion.
  confirmed,

  /// The user picked this feeling in place of what the analyser suggested.
  overridden,

  /// No source recorded, or a value this build does not recognise.
  unset;

  /// Resolves a wire feeling-source string; anything unrecognised is
  /// [unset]. Never throws.
  static FeelingSource fromWire(String? raw) => switch (raw) {
    'suggested' => FeelingSource.suggested,
    'confirmed' => FeelingSource.confirmed,
    'overridden' => FeelingSource.overridden,
    _ => FeelingSource.unset,
  };

  /// Whether a feeling from this source counts as evidence.
  ///
  /// Only a feeling the user acted on does. A suggestion the analyser made
  /// that nobody looked at is not a fact about the day, and the same rule
  /// decides it on the backend — this is the client reading the label,
  /// never re-deciding the rule.
  bool get isConfirmed =>
      this == FeelingSource.confirmed || this == FeelingSource.overridden;
}

/// One answered guiding question, as stored with the entry.
///
/// [questionText] is the snapshot the backend kept of how the question was
/// worded at the time, not the current wording — a question the library has
/// since reworded must still be shown as the one that was actually
/// answered.
class const GuidedAnswer(
  final String questionKey,
  final String questionText,
  final String answerText,
);

/// One feeling the analyser proposed, and how sure it was.
class const SuggestedFeeling(final Feeling feeling, final double confidence);

/// A single diary entry. Entries are never merged — each has its own id and
/// timestamp even if several exist on the same [entryDate].
class const Entry(
  final String id,
  final DateTime createdAt,
  final CalendarDate entryDate,
  final EntryMode mode,
  final String rawText,

  /// The entry's primary feeling — always the first of [feelings], or null
  /// when nothing is chosen. It is what the calendar dot and the entry
  /// card's rail are keyed on.
  final Feeling? feeling,

  /// Every feeling on the entry, in the order they were chosen.
  final List<Feeling> feelings,
  final FeelingSource feelingSource,

  /// How strongly the primary feeling was felt, 1-5, or null when the user
  /// never said.
  ///
  /// Optional by requirement. The analyser's confidence is a different
  /// quantity measured on a different thing — how sure the model is, not
  /// how much the user felt — and is never shown here.
  final int? feelingIntensity,

  /// How strongly each feeling on this entry was felt, keyed by
  /// [Feeling.key].
  ///
  /// Only feelings the user rated appear. An absent key means the question
  /// was never answered, which is a different thing from a low rating, so
  /// nothing here defaults to a number. [feelingIntensity] is this map read
  /// at the primary feeling and exists for the calendar, which draws one
  /// dot and needs one number.
  final Map<String, int> feelingIntensities,

  /// The guided questions this entry was written against, in order, with
  /// the wording they were answered under. Empty for a freeform entry, and
  /// empty when the screen has not loaded them.
  final List<GuidedAnswer> guidedAnswers,
  final SuggestedFeeling? suggestedFeeling,

  /// Everything the analyser proposed, strongest first. Empty when it has
  /// nothing to add.
  final List<SuggestedFeeling> suggestedFeelings,

  /// The entry revision marker. Carries no diary content — it exists so an
  /// edit or delete can say which version of the entry it was based on, and
  /// so the backend can reject a change made from a view that another
  /// client has already moved past. Every mutation must send back the
  /// version it read; a mismatch comes back as `409`.
  final int version, {

  /// True while the backend is (re)analysing this entry's text.
  ///
  /// Editing the text re-queues topic extraction, and the analyser's
  /// verdict — including any changed feeling — only lands once that
  /// finishes. A client that has just saved an edit waits on this rather
  /// than reading a stale [suggestedFeeling] from the moment before its own
  /// edit.
  final bool analysisPending = false,
});

/// Matches a trailing `Z` or a numeric UTC offset such as `+02:00`.
final RegExp _zonePattern = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

/// Parses a backend timestamp into a UTC instant.
///
/// The backend's timestamps are a UTC wall clock serialised with **no**
/// timezone designator — `2026-08-26T09:00:00.000000`, not
/// `2026-08-26T09:00:00.000000Z`. [DateTime.parse] treats an unmarked
/// string as local time, which would silently shift every timestamp by the
/// device's offset from UTC, so an unmarked string is given an explicit `Z`
/// before parsing. A string that already carries a zone (as a hand-built
/// fixture might) is left alone. Falls back to the epoch, exactly as the
/// Kotlin client does, rather than throwing on a string this build cannot
/// read.
DateTime _parseInstant(String raw) {
  try {
    final normalized = _zonePattern.hasMatch(raw) ? raw : '${raw}Z';
    return DateTime.parse(normalized).toUtc();
  } on FormatException {
    return DateTime.utc(1970);
  }
}

/// Decodes one `EntryDto` wire object into an [Entry], resolving feeling
/// keys through [catalog].
///
/// A function rather than a factory constructor, because turning a wire
/// `feeling_key` into a domain [Feeling] needs the backend-served catalog —
/// there is no `Entry.fromJson` that does not also need one of these.
Entry entryFromJson(JsonObject json, FeelingCatalog catalog) {
  final feelingKey = json['feeling_key'] as String?;
  final feelingKeys = (json['feeling_keys'] as List<Object?>?)?.cast<String>();
  final suggestedFeeling = json['suggested_feeling'] as JsonObject?;
  final suggestedFeelings =
      (json['suggested_feelings'] as List<Object?>?)?.cast<JsonObject>() ??
      const [];
  final guidedAnswers = (json['guided_answers'] as List<Object?>?)
      ?.cast<JsonObject>();
  final feelingIntensities =
      (json['feeling_intensities'] as JsonObject?)?.cast<String, int>() ??
      const {};

  return Entry(
    json['id']! as String,
    _parseInstant(json['created_at']! as String),
    CalendarDate.parse(json['entry_date']! as String),
    EntryMode.fromWire(json['mode']! as String),
    json['raw_text']! as String,
    catalog.fromKey(feelingKey),
    // An older backend sends only `feeling_key`; reading that as the set of
    // one keeps such an entry showing its feeling rather than showing none.
    catalog.fromKeys(
      feelingKeys != null && feelingKeys.isNotEmpty
          ? feelingKeys
          : [?feelingKey],
    ),
    FeelingSource.fromWire(json['feeling_source'] as String?),
    json['feeling_intensity'] as int?,
    feelingIntensities,
    // Null means this endpoint did not load them; both readings are
    // "nothing to lay out here".
    [
      for (final dto in guidedAnswers ?? const [])
        GuidedAnswer(
          dto['question_key']! as String,
          dto['question_text']! as String,
          dto['answer_text']! as String,
        ),
    ],
    _suggestedFeelingFromJson(suggestedFeeling, catalog),
    [
      for (final dto in suggestedFeelings)
        ?_suggestedFeelingFromJson(dto, catalog),
    ],
    json['version']! as int,
    analysisPending: json['analysis_pending'] as bool? ?? false,
  );
}

SuggestedFeeling? _suggestedFeelingFromJson(
  JsonObject? json,
  FeelingCatalog catalog,
) {
  if (json == null) return null;
  final feeling = catalog.fromKey(json['key'] as String?);
  if (feeling == null) return null;
  return SuggestedFeeling(feeling, (json['confidence']! as num).toDouble());
}
