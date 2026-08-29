import '../config/app_config.dart';
import '../network/api_client.dart';
import 'calendar_date.dart';
import 'feelings_api.dart';
import 'monthly_summary.dart';

/// Talks to `GET /monthly-summary`, which powers the monthly calendar
/// screen.
class MonthlySummaryApi {
  /// Creates an API over an [ApiClient], resolving feeling keys through a
  /// [FeelingsApi].
  MonthlySummaryApi(this._client, this._feelings);

  final ApiClient _client;
  final FeelingsApi _feelings;

  /// The day-by-day summary for [month].
  Future<MonthlySummary> forMonth(YearMonth month) async {
    final catalog = await _feelings.catalog();
    return _client.getObject(
      '${AppConfig.monthlySummaryPath}?month=$month',
      (json) => monthlySummaryFromJson(json, catalog),
    );
  }
}
