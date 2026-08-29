import '../network/api_client.dart';
import 'calendar_date.dart';
import 'feeling.dart';

/// Per-day breakdown for the monthly calendar grid.
class const DaySummary(
  final CalendarDate date,
  final List<Feeling> feelings, {

  /// The strongest intensity recorded on this day, or null when nothing
  /// was rated.
  ///
  /// The maximum rather than the mean, and the backend decides which: the
  /// cell answers "how much did this day register", and averaging a rated
  /// 5 with two unrated entries would report a quieter day than the one
  /// the user had.
  final int? intensity,
});

/// Powers the monthly calendar screen, from `GET /monthly-summary`.
class const MonthlySummary(
  final YearMonth month,
  final List<DaySummary> days,
  final Map<Feeling, int> totalsByFeeling,
  final double averageEntriesPerDay,
);

/// Decodes one day's summary.
DaySummary daySummaryFromJson(JsonObject json, FeelingCatalog catalog) =>
    DaySummary(
      CalendarDate.parse(json['date']! as String),
      catalog.fromKeys(
        (json['feelings'] as List<Object?>?)?.cast<String>() ?? const [],
      ),
      intensity: json['intensity'] as int?,
    );

/// Decodes `GET /monthly-summary`'s whole response.
///
/// [now] lets a caller pin the clock a bare `month` falls back to, instead
/// of this reaching for the real one — the same reason [CalendarDate.today]
/// takes one.
MonthlySummary monthlySummaryFromJson(
  JsonObject json,
  FeelingCatalog catalog, {
  DateTime? now,
}) {
  final totals = (json['totals_by_feeling'] as JsonObject?) ?? const {};
  return MonthlySummary(
    YearMonth.tryParse(json['month'] as String?) ?? YearMonth.current(now: now),
    [
      for (final dto
          in (json['days'] as List<Object?>?)?.cast<JsonObject>() ??
              const <JsonObject>[])
        daySummaryFromJson(dto, catalog),
    ],
    // Built by walking the catalog rather than the response so the totals
    // panel lists feelings in the backend's own (stable) order without the
    // UI having to know what that order is.
    {
      for (final feeling in catalog.feelings)
        feeling: ?totals[feeling.key] as int?,
    },
    (json['average_entries_per_day'] as num?)?.toDouble() ?? 0.0,
  );
}
