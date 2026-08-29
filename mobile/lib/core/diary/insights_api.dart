import '../config/app_config.dart';
import '../network/api_client.dart';
import '../network/api_error.dart';
import 'calendar_date.dart';
import 'digest.dart';
import 'feelings_api.dart';
import 'mood_series.dart';
import 'pattern.dart';

/// Talks to `GET /insights`, `GET /insights/when`, `GET /insights/series`,
/// `GET /insights/digest`, and the withdrawal acknowledgement endpoint.
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

  /// The daily mood series behind the Insights mood-trend chart, and the
  /// Today screen's writing streak (#40), from [from] to [to] inclusive.
  ///
  /// Always requested at day granularity: every period the chart currently
  /// offers -- 30 days, 90 days, the last year -- fits under the endpoint's
  /// day-granularity range cap, so there is nothing for a `week`/`month`
  /// choice to buy this client yet. The streak reads [MoodSeries.points]'s
  /// dates as the set of days with at least one entry -- a day with nothing
  /// written is simply absent from the array, never sent as a zero point.
  Future<MoodSeries> series({
    required CalendarDate from,
    required CalendarDate to,
  }) => _client.getObject(
    '${AppConfig.seriesPath}?from=$from&to=$to&granularity=day',
    moodSeriesFromJson,
  );

  /// [R-2] The current week's digest -- one highlight pattern, one
  /// recommendation, one movement figure, or the empty shape when nothing
  /// was written this week.
  ///
  /// Called only when the digest sheet opens (a tap on the weekly digest
  /// notification), never when that notification is merely scheduled or
  /// shown -- see `mobile/lib/core/notifications/reminder_service.dart`'s
  /// digest copy doc comment for why the notification itself never carries
  /// digest content. A caller that gets an [ApiError] here (the backend is
  /// unreachable) falls back to opening Insights instead of showing a sheet
  /// with nothing in it -- see `app.dart`'s digest-tap handler.
  Future<Digest> digest() async {
    final catalog = await _feelings.catalog();
    return _client.getObject(
      AppConfig.digestPath,
      (json) => digestFromJson(json, catalog),
    );
  }

  /// Marks every current withdrawal notice as seen.
  ///
  /// A deliberate `POST`, not a side effect of [insights] — if opening
  /// Insights cleared the flag on its own, whichever device opened it first
  /// would clear it for the other.
  Future<void> acknowledgeWithdrawals() =>
      _client.post(AppConfig.withdrawalAcknowledgePath);
}
