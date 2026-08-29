import '../config/app_config.dart';
import '../network/api_client.dart';
import 'guiding_question.dart';

GuidingQuestion _guidingQuestionFromJson(JsonObject json) => GuidingQuestion(
  json['key']! as String,
  QuestionCategory.fromWire(json['category'] as String?),
  json['prompt_text']! as String,
  (json['trigger_keywords'] as List<Object?>?)?.cast<String>() ?? const [],
  json['is_mandatory'] as bool? ?? false,
);

List<GuidingQuestion> _libraryFromJson(JsonObject json) => [
  for (final dto
      in (json['questions'] as List<Object?>?)?.cast<JsonObject>() ??
          const <JsonObject>[])
    _guidingQuestionFromJson(dto),
];

/// Talks to `GET /guiding-questions` and caches the whole library in memory
/// for the life of this object, so [matchingOptionalQuestions] can match
/// against it without a network call on every entry-composer open.
///
/// Like `FeelingsApi`, [library] holds the in-flight request while one is
/// outstanding, so two callers racing on a cold cache produce one HTTP
/// request rather than two.
class GuidingQuestionsApi {
  /// Creates an API over an [ApiClient].
  GuidingQuestionsApi(this._client);

  final ApiClient _client;

  List<GuidingQuestion>? _cached;
  Future<List<GuidingQuestion>>? _inFlight;

  /// The guiding-question library.
  ///
  /// Cached after the first successful fetch; pass [forceRefresh] to bypass
  /// that and hit the network again.
  Future<List<GuidingQuestion>> library({bool forceRefresh = false}) {
    if (_cached case final cached? when !forceRefresh) {
      return Future.value(cached);
    }
    if (_inFlight case final pending? when !forceRefresh) {
      return pending;
    }
    final request = _load();
    _inFlight = request;
    return request;
  }

  Future<List<GuidingQuestion>> _load() async {
    try {
      final library = await _client.getObject(
        AppConfig.guidingQuestionsPath,
        _libraryFromJson,
      );
      _cached = library;
      return library;
    } finally {
      _inFlight = null;
    }
  }
}
