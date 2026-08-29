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

  /// How many entries were logged this day.
  ///
  /// Deliberately not `feelings.length`: [feelings] is the *distinct set*
  /// of feelings seen that day, so ten entries all tagged the same feeling
  /// still leave `feelings.length == 1` while `entryCount` reads 10. The
  /// calendar's volume bar reads this field precisely because
  /// `feelings.length` used to stand in for it and undercounted busy days.
  ///
  /// Defaults to 0 so a [DaySummary] built by hand (this file's own tests,
  /// the today screen's day-summary card) does not have to state a count
  /// it does not care about; a real one is always populated by
  /// [daySummaryFromJson].
  final int entryCount = 0,
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
      // Null-tolerant like every other optional field here: a backend that
      // predates #72 has no `entry_count` key at all, and that must decode
      // as "nothing here" (0) rather than throw.
      entryCount: json['entry_count'] as int? ?? 0,
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
