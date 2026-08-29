import '../config/app_config.dart';
import '../network/api_client.dart';
import 'feelings_api.dart';
import 'pattern.dart';

/// Talks to `GET /insights`, `GET /insights/when`, and the withdrawal
/// acknowledgement endpoint.
class InsightsApi {
  /// Creates an API over an [ApiClient], resolving feeling keys through a
  /// [FeelingsApi].
  InsightsApi(this._client, this._feelings);

  final ApiClient _client;
  final FeelingsApi _feelings;

  /// The detected patterns and any pending withdrawals.
  ///
  /// This endpoint recomputes on the backend before answering, so every
  /// call can return different numbers even with nothing new written.
  Future<InsightsResult> insights() async {
    final catalog = await _feelings.catalog();
    return _client.getObject(
      AppConfig.insightsPath,
      (json) => insightsResultFromJson(json, catalog),
    );
  }

  /// The weekday and time-of-day breakdown behind the "when" panel.
  Future<WhenInsights> whenInsights() =>
      _client.getObject(AppConfig.insightsWhenPath, whenInsightsFromJson);

  /// Marks every current withdrawal notice as seen.
  ///
  /// A deliberate `POST`, not a side effect of [insights] — if opening
  /// Insights cleared the flag on its own, whichever device opened it first
  /// would clear it for the other.
  Future<void> acknowledgeWithdrawals() =>
      _client.post(AppConfig.withdrawalAcknowledgePath);
}
