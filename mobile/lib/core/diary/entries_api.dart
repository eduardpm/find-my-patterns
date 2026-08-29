import '../config/app_config.dart';
import '../network/api_client.dart';
import '../network/api_error.dart';
import 'calendar_date.dart';
import 'entry.dart';
import 'feeling.dart';
import 'feelings_api.dart';
import 'guiding_question.dart';
import 'pattern.dart';

/// The outcome of a mutation that carried a version.
///
/// [ApiError] is sealed and cannot be extended from outside its own
/// library, so a version conflict is modelled here instead of as a new
/// [ApiError] subtype.
sealed class const EntryMutation();

/// The mutation was applied; [entry] is the entry as now stored.
final class const EntryUpdated(final Entry entry) extends EntryMutation;

/// The entry was deleted.
final class const EntryRemoved() extends EntryMutation;

/// Nothing changed: the version was out of date. [current] is the entry as
/// actually stored, so a screen can show both versions without a second
/// round trip.
final class const EntryOutOfDate(final String message, final Entry current)
    extends EntryMutation;

/// Builds the wire body for `PATCH /entries/{id}`.
///
/// [version] is always sent — omitting it is a 422, since the backend has
/// no way to tell a deliberate edit from one based on a stale view. Every
/// other field is included only when the caller actually passed something,
/// because an absent field means "leave it alone":
///
/// * [text] becomes `raw_text` only when non-null.
/// * [feelings] becomes `feeling_keys` only when non-null **and
///   non-empty** — an empty list is sent as absent, not as `[]`, because
///   there is no way to clear an entry's feelings and doing so is almost
///   always a bug rather than an intention.
/// * [intensities] becomes `feeling_intensities` whenever it is non-null,
///   empty map included: an empty map is how every rating is cleared,
///   which is different from not touching them at all.
///
/// The legacy scalar `feeling_intensity` is never sent; this client always
/// sends the (possibly single-element) `feeling_keys` list instead.
JsonObject buildUpdateBody({
  required int version,
  String? text,
  List<Feeling>? feelings,
  Map<String, int>? intensities,
}) => {
  'version': version,
  'raw_text': ?text,
  if (feelings != null && feelings.isNotEmpty)
    'feeling_keys': [for (final feeling in feelings) feeling.key],
  'feeling_intensities': ?intensities,
};

/// Parses a `409 stale_entry` body into [EntryOutOfDate].
///
/// The envelope is `{"error": {"code": ..., "message": ...}, "current":
/// {...entry...}}`. Returns null when [body] is not that shape — a 409
/// whose body cannot be read this way is still a conflict, just without the
/// comparison, and the caller is expected to rethrow the original failure
/// rather than invent a `current` entry.
EntryOutOfDate? entryMutationFromConflict(
  Object? body,
  FeelingCatalog catalog,
) {
  if (body is! JsonObject) return null;
  final error = body['error'];
  final current = body['current'];
  if (error is! JsonObject || current is! JsonObject) return null;
  final message = error['message'];
  if (message is! String) return null;
  return EntryOutOfDate(message, entryFromJson(current, catalog));
}

/// One topic assigned to one feeling, as sent to [EntriesApi.setTopicFeelings]
/// -- the input side of `PUT /entries/{id}/topic-feelings` (E-1a/E-1c).
///
/// Deliberately carries no `source`: `topicFeelingPairingInputSchema`
/// (`backend/src/common/validation.ts`) has no such field, and
/// `EntriesService.setTopicFeelingPairings` derives `confirmed` vs
/// `overridden` itself, per pair, by comparing each one against what the
/// analyser last suggested. This client only ever reports the pairing the
/// user landed on, never a verdict about how it got there.
typedef TopicFeelingAssignment = ({String topicId, String feelingKey});

/// Talks to `POST/PATCH/DELETE/GET /entries` and maps wire DTOs onto the
/// domain [Entry] model.
///
/// Every method throws [ApiError] on failure. Mutations additionally carry
/// the version they were based on and translate the backend's `409` into
/// [EntryOutOfDate], so a caller can tell "your view was out of date, here
/// is what's actually stored" apart from an ordinary server error.
class EntriesApi {
  /// Creates an API over an [ApiClient], resolving feeling keys through a
  /// [FeelingsApi].
  EntriesApi(this._client, this._feelings);

  final ApiClient _client;
  final FeelingsApi _feelings;

  /// Creates a freeform entry from [text].
  ///
  /// [entryDate] backdates the entry (#36) — omitted, the backend files it
  /// under its own idea of today, exactly as before. A caller only passes
  /// this when the composer is explicitly writing for a day other than
  /// today, so the ordinary "write for today" path never risks the
  /// server's and device's clocks disagreeing about what "today" means.
  Future<Entry> createFreeform(String text, {CalendarDate? entryDate}) async {
    final catalog = await _feelings.catalog();
    return _client.postObject(
      AppConfig.entriesPath,
      (json) => entryFromJson(json, catalog),
      body: {
        'mode': 'freeform',
        'raw_text': text,
        if (entryDate != null) 'entry_date': entryDate.toString(),
      },
    );
  }

  /// Creates a guided entry from [answers].
  ///
  /// `raw_text` is deliberately sent empty — the backend composes the
  /// prose from the answers, prompt on its own line and answer under it, so
  /// this client does not join them itself. See [createFreeform] for
  /// [entryDate].
  Future<Entry> createGuided(
    List<GuidingQuestionAnswer> answers, {
    CalendarDate? entryDate,
  }) async {
    final catalog = await _feelings.catalog();
    return _client.postObject(
      AppConfig.entriesPath,
      (json) => entryFromJson(json, catalog),
      body: {
        'mode': 'guided',
        'raw_text': '',
        'guided_answers': [
          for (final answer in answers)
            {
              'question_key': answer.questionKey,
              'answer_text': answer.answerText,
            },
        ],
        if (entryDate != null) 'entry_date': entryDate.toString(),
      },
    );
  }

  /// Lists every entry written on [date].
  Future<List<Entry>> listByDate(CalendarDate date) async {
    final catalog = await _feelings.catalog();
    return _client.getObject(
      '${AppConfig.entriesPath}?date=$date',
      (json) => [
        for (final dto
            in (json['entries'] as List<Object?>?)?.cast<JsonObject>() ??
                const <JsonObject>[])
          entryFromJson(dto, catalog),
      ],
    );
  }

  /// Reads one entry by [id].
  Future<Entry> getById(String id) async {
    final catalog = await _feelings.catalog();
    return _client.getObject(
      AppConfig.entryPath(id),
      (json) => entryFromJson(json, catalog),
    );
  }

  /// What the diary already says about the topics in the entry [id] —
  /// asked only after the entry is stored.
  Future<List<PatternEcho>> echo(String id) => _client.getObject(
    AppConfig.entryEchoPath(id),
    (json) => [
      for (final dto
          in (json['echoes'] as List<Object?>?)?.cast<JsonObject>() ??
              const <JsonObject>[])
        patternEchoFromJson(dto),
    ],
  );

  /// General edit: either [text] or [feelings] may be omitted to leave it
  /// unchanged.
  ///
  /// Sends `PATCH /entries/{id}` — see [buildUpdateBody] for exactly what
  /// goes in the body.
  Future<EntryMutation> update({
    required String id,
    required int version,
    String? text,
    List<Feeling>? feelings,
    Map<String, int>? intensities,
  }) => _patch(
    id,
    buildUpdateBody(
      version: version,
      text: text,
      feelings: feelings,
      intensities: intensities,
    ),
  );

  /// Confirms or overrides the suggested feelings for entry [id].
  ///
  /// Same PATCH as [update], with only the feelings (and optionally their
  /// intensities) changing.
  Future<EntryMutation> confirmFeelings({
    required String id,
    required int version,
    required List<Feeling> feelings,
    Map<String, int> intensities = const {},
  }) => _patch(
    id,
    buildUpdateBody(
      version: version,
      feelings: feelings,
      intensities: intensities,
    ),
  );

  /// Stores the confirmed/overridden topic↔feeling pairing set for entry
  /// [id] (E-1a/E-1c), replacing whatever was stored before, via
  /// `PUT /entries/{id}/topic-feelings`.
  ///
  /// **Skipping the pairing step must never call this with an empty
  /// [pairings] list.** `topicFeelingsUpdateSchema`'s own doc comment
  /// (`backend/src/common/validation.ts`) calls an empty array "a
  /// legitimate answer: none of these topics pair with a feeling" -- an
  /// affirmative, stored decision. Per `excludedUnpaired` in
  /// `backend/src/insights/patterns.service.ts`, that decision permanently
  /// excludes the entry from mixed-valence counting, and
  /// `EntriesService.setTopicFeelingPairings` deletes the entry's whole
  /// `entry_topic_feelings` row set -- including the analyser's own
  /// `'suggested'` rows -- before writing whatever was sent. A genuine skip
  /// (E-1c task 3, "skipped pairings are never guessed") must leave the
  /// entry exactly as it was: still carrying zero *confirmed* rows (so
  /// `excludedUnpaired` still counts it as unpaired, precisely the state a
  /// skip is supposed to reach), but with the `'suggested'` rows intact for
  /// later. There is deliberately no `EntriesApi` method for "skip" --
  /// simply not calling this one is what skipping means.
  ///
  /// No `version` travels with this call, unlike [update]/[confirmFeelings]:
  /// `topicFeelingsUpdateSchema` carries no such field, so this endpoint has
  /// no optimistic-concurrency check of its own and there is no `409`/
  /// [EntryMutation] case to translate here.
  Future<Entry> setTopicFeelings({
    required String id,
    required List<TopicFeelingAssignment> pairings,
  }) async {
    final catalog = await _feelings.catalog();
    return _client.putObject(
      AppConfig.entryTopicFeelingsPath(id),
      (json) => entryFromJson(json, catalog),
      body: {
        'pairings': [
          for (final pairing in pairings)
            {'topic_id': pairing.topicId, 'feeling_key': pairing.feelingKey},
        ],
      },
    );
  }

  Future<EntryMutation> _patch(String id, JsonObject body) async {
    final catalog = await _feelings.catalog();
    try {
      final entry = await _client.patchObject(
        AppConfig.entryPath(id),
        (json) => entryFromJson(json, catalog),
        body: body,
      );
      return EntryUpdated(entry);
    } on HttpFailure catch (failure) {
      if (failure.statusCode != 409) rethrow;
      final conflict = entryMutationFromConflict(failure.body, catalog);
      if (conflict == null) rethrow;
      return conflict;
    }
  }

  /// Deletes the entry the caller last read.
  ///
  /// A [version] that is no longer current comes back as [EntryOutOfDate]
  /// and nothing is deleted — the caller decides whether to delete the
  /// version it has now been shown.
  Future<EntryMutation> deleteById({
    required String id,
    required int version,
  }) async {
    // Fetched up front, matching every other method here, even though only
    // the conflict path needs it — [FeelingsApi] caches after the first
    // call, so this costs a real request only once per process.
    final catalog = await _feelings.catalog();
    try {
      await _client.delete('${AppConfig.entryPath(id)}?version=$version');
      return const EntryRemoved();
    } on HttpFailure catch (failure) {
      if (failure.statusCode != 409) rethrow;
      final conflict = entryMutationFromConflict(failure.body, catalog);
      if (conflict == null) rethrow;
      return conflict;
    }
  }
}
