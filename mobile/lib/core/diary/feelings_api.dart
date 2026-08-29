import '../config/app_config.dart';
import '../network/api_client.dart';
import 'feeling.dart';

Valence _valenceFromJson(JsonObject json) =>
    Valence.fromWire(json['valence'] as String?);

Feeling _feelingFromJson(JsonObject json) => Feeling(
  json['key']! as String,
  json['label']! as String,
  _valenceFromJson(json),
  json['group_key'] as String? ?? '',
);

FeelingGroup _feelingGroupFromJson(JsonObject json) => FeelingGroup(
  json['key']! as String,
  json['label']! as String,
  _valenceFromJson(json),
  [
    for (final dto
        in (json['feelings'] as List<Object?>?)?.cast<JsonObject>() ??
            const <JsonObject>[])
      _feelingFromJson(dto),
  ],
);

FeelingCatalog _catalogFromJson(JsonObject json) => FeelingCatalog(
  [
    for (final dto
        in (json['feelings'] as List<Object?>?)?.cast<JsonObject>() ??
            const <JsonObject>[])
      _feelingFromJson(dto),
  ],
  groups: [
    for (final dto
        in (json['groups'] as List<Object?>?)?.cast<JsonObject>() ??
            const <JsonObject>[])
      _feelingGroupFromJson(dto),
  ],
);

/// Talks to `GET /feelings` and caches the result for the life of this
/// object.
///
/// The feeling set changes only when the backend's reference data does, so
/// one fetch per process is plenty — `GuidingQuestionsApi` applies the same
/// reasoning to its own library. Every mapper that turns a wire
/// `feeling_key` into a domain [Feeling] needs this catalog, so it is
/// worth caching well: [catalog] holds the in-flight request itself while
/// one is outstanding, so two callers racing on a cold cache produce one
/// HTTP request, not two.
class FeelingsApi {
  /// Creates an API over an [ApiClient].
  FeelingsApi(this._client);

  final ApiClient _client;

  FeelingCatalog? _cached;
  Future<FeelingCatalog>? _inFlight;

  /// The feeling set as a lookup, for resolving wire `feeling_key`s.
  ///
  /// Cached after the first successful fetch; pass [forceRefresh] to bypass
  /// that and hit the network again.
  Future<FeelingCatalog> catalog({bool forceRefresh = false}) {
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

  Future<FeelingCatalog> _load() async {
    try {
      final catalog = await _client.getObject(
        AppConfig.feelingsPath,
        _catalogFromJson,
      );
      _cached = catalog;
      return catalog;
    } finally {
      _inFlight = null;
    }
  }

  /// The feeling set for display, e.g. by a feeling picker.
  Future<List<Feeling>> feelings({bool forceRefresh = false}) async =>
      (await catalog(forceRefresh: forceRefresh)).feelings;

  /// The same set nested into the groups the picker's first level shows.
  Future<List<FeelingGroup>> groups({bool forceRefresh = false}) async =>
      (await catalog(forceRefresh: forceRefresh)).groups;
}
