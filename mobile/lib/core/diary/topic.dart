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

/// One topic linked to an entry (#81), as served on `entries[].topics` --
/// just the id and name, unlike [TopicDetail]'s full read of `GET /topics`.
///
/// Sourced on the backend from `TopicsService.topicsForEntry()`, so it
/// carries every topic the engine extracted for the entry, including one it
/// could not pair with any feeling. `entries[].topic_feelings` (E-1a) is a
/// different, narrower list: one row per (topic, feeling) pair, so a topic
/// with no pairing has no row there at all. This type -- not that one -- is
/// what a client reads to show every topic an entry has, paired or not.
class const Topic(final String id, final String name);

/// Decodes one entry topic.
Topic topicFromJson(JsonObject json) =>
    Topic(json['id']! as String, json['name']! as String);
