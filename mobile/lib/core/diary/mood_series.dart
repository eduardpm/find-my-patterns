import '../network/api_client.dart';
import 'calendar_date.dart';

/// One day of `GET /insights/series`, at day granularity.
///
/// [score] is null on a day that was logged but carries no confirmed
/// feeling -- a suggestion nobody confirmed is not evidence, so it moves
/// [entryCount] but never the score (see the day-score contract in the
/// backend's `constants.ts`). A day with *no* entries at all is not
/// represented in [MoodSeries.points] as a point with a zero count; it is
/// left out of the array entirely, so a caller has to compare dates to
/// notice it is missing rather than scan for a sentinel.
class const MoodSeriesPoint(
  final CalendarDate date,
  final double? score,
  final int entryCount,
  final int confirmedFeelingCount,
);

/// `GET /insights/series`'s response, restricted to what the mood-trend
/// chart needs.
///
/// `granularity` and `constants` are dropped after decoding: this client
/// always asks for day granularity (see `MoodTrendController`), and the
/// chart's own "not enough days yet" threshold is a client concern, not one
/// the engine publishes.
class const MoodSeries(final List<MoodSeriesPoint> points);

double? _toDouble(Object? value) => (value as num?)?.toDouble();

/// Decodes one point of `GET /insights/series`.
MoodSeriesPoint moodSeriesPointFromJson(JsonObject json) => MoodSeriesPoint(
  CalendarDate.parse(json['date']! as String),
  _toDouble(json['score']),
  json['entry_count'] as int? ?? 0,
  json['confirmed_feeling_count'] as int? ?? 0,
);

/// Decodes `GET /insights/series`'s whole response.
MoodSeries moodSeriesFromJson(JsonObject json) => MoodSeries([
  for (final dto
      in (json['points'] as List<Object?>?)?.cast<JsonObject>() ??
          const <JsonObject>[])
    moodSeriesPointFromJson(dto),
]);
