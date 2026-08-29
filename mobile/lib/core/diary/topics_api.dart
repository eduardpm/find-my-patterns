import '../config/app_config.dart';
import '../network/api_client.dart';
import 'topic.dart';

/// Talks to `GET /topics` and its alias endpoints.
///
/// Aliases are the half of topic normalisation the backend cannot decide
/// alone — "gym session" is exercise in most diaries and something else in
/// a physiotherapist's. The rules that hold for everyone live in the
/// backend's canonical list; this is where one person's vocabulary goes.
class TopicsApi {
  /// Creates an API over an [ApiClient].
  TopicsApi(this._client);

  final ApiClient _client;

  /// Every topic and its aliases.
  Future<List<TopicDetail>> list() => _client.getObject(
    AppConfig.topicsPath,
    (json) => [
      for (final dto
          in (json['topics'] as List<Object?>?)?.cast<JsonObject>() ??
              const <JsonObject>[])
        topicDetailFromJson(dto),
    ],
  );

  /// Teaches [topicId] a new spelling, [alias].
  Future<TopicDetail> addAlias(String topicId, String alias) =>
      _client.postObject(
        AppConfig.topicAliasesPath(topicId),
        topicDetailFromJson,
        body: {'alias': alias},
      );

  /// Forgets [alias] on [topicId].
  ///
  /// The backend's `DELETE` for this route answers with the topic as it now
  /// stands, which saves a round trip a fresh [list] call would otherwise
  /// need.
  Future<TopicDetail> removeAlias(String topicId, String alias) =>
      _client.deleteObject(
        AppConfig.topicAliasPath(topicId, alias),
        topicDetailFromJson,
      );
}
