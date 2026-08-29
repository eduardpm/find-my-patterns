import '../network/api_client.dart';

/// A topic and the spellings the user has taught the app to fold into it.
///
/// Aliases are the half of topic normalisation the backend cannot decide
/// alone — "gym session" is exercise in most diaries and something else in
/// a physiotherapist's. The rules that hold for everyone live in the
/// backend's canonical list; this is where one person's vocabulary goes,
/// with no model asked to guess.
class const TopicDetail(
  final String id,
  final String name,
  final List<String> aliases,
  final int entryCount,
);

/// Decodes one topic.
TopicDetail topicDetailFromJson(JsonObject json) => TopicDetail(
  json['id']! as String,
  json['name']! as String,
  (json['aliases'] as List<Object?>?)?.cast<String>() ?? const [],
  json['entry_count'] as int? ?? 0,
);
