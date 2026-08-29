import '../config/app_config.dart';
import '../network/api_client.dart';
import '../network/api_error.dart';
import 'experiment.dart';

/// Talks to `POST /experiments`, `GET /experiments/active`,
/// `POST /experiments/{id}/abandon` and `GET /experiments/{id}/results`
/// (R-3a).
///
/// Eligibility is the backend's call, never this client's: [create] sends
/// exactly the topic, feeling, hypothesis and length asked for, and a
/// non-qualifying pattern or an experiment already running come back as a
/// 422 [HttpFailure] with the backend's own message -- this client never
/// re-derives "does this pattern qualify" itself before sending the
/// request (`experiments.service.ts`'s doc comment states the same rule
/// from the other side).
class ExperimentsApi {
  /// Creates an API over an [ApiClient].
  ExperimentsApi(this._client);

  final ApiClient _client;

  /// Starts a new experiment on [patternTopic]/[patternFeeling].
  ///
  /// [lengthDays] is omitted when the caller wants the backend's own
  /// default ([ExperimentConstants.defaultLengthDays]) rather than sending
  /// a client-side guess at it.
  Future<Experiment> create({
    required String patternTopic,
    required String patternFeeling,
    required HypothesisKind hypothesisKind,
    int? lengthDays,
  }) => _client.postObject(
    AppConfig.experimentsPath,
    experimentFromJson,
    body: {
      'pattern_topic': patternTopic,
      'pattern_feeling': patternFeeling,
      'hypothesis_kind': hypothesisKind.wireValue,
      'length_days': ?lengthDays,
    },
  );

  /// The currently active experiment, or `null` when none is running.
  ///
  /// `GET /experiments/active` answers `404` for "nothing is active" --
  /// the same shape as any other not-found response -- and that is a
  /// normal, expected reading of this endpoint rather than a failure, so
  /// it is translated to `null` here rather than left for every caller to
  /// catch [HttpFailure] and check its status by hand. Any other
  /// [ApiError] (unreachable server, unconfigured backend, …) still
  /// propagates -- that is a real failure to fetch, not "no experiment".
  ///
  /// A `200` whose body does not actually decode as an experiment --
  /// [experimentFromJson] asserting a required field non-null against one
  /// that is absent -- is treated the same as "nothing running" rather
  /// than crashing whatever screen's best-effort banner asked for this: a
  /// malformed reply is no more actionable here than a plain absence.
  Future<Experiment?> active() async {
    try {
      return await _client.getObject(
        AppConfig.experimentActivePath,
        experimentFromJson,
      );
    } on HttpFailure catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    } on TypeError {
      return null;
    }
  }

  /// Abandons the experiment [id]. Always available while it is active
  /// (backend's own rule); refused with a 422 once it is already finished
  /// or abandoned.
  Future<Experiment> abandon(String id) => _client.postObject(
    AppConfig.experimentAbandonPath(id),
    experimentFromJson,
  );

  /// The two-window comparison and verdict for experiment [id].
  Future<ExperimentResults> results(String id) => _client.getObject(
    AppConfig.experimentResultsPath(id),
    experimentResultsFromJson,
  );
}
