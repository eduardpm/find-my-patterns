/// @docImport '../../core/diary/insights_api.dart';
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/diary_providers.dart';
import '../../core/diary/mood_series.dart';
import '../../core/network/api_error.dart';
import 'calendar_controller.dart';

/// The Year in Pixels screen's state: the year currently shown, its points
/// once loaded, and the most recent failure that has not yet been shown.
///
/// Mirrors [CalendarState] field for field, including the same
/// [hasLoaded]/[errorMessage] pairing and the same reason for each: a
/// summary line good enough to read needs to know the difference between
/// "still loading" and "loaded, nothing written yet".
class const YearGridState({
  required final int year,
  final List<MoodSeriesPoint> points = const [],
  final bool hasLoaded = false,
  final String? errorMessage,
}) {
  /// Distinguishes "leave [errorMessage] alone" from "clear it" in
  /// [copyWith] — see [CalendarState.copyWith] for why a plain `??` cannot
  /// do this.
  static const Object _unset = Object();

  /// A copy of this state with the given fields replaced.
  ///
  /// Pass `errorMessage: null` to explicitly clear it; omit it to leave the
  /// current value alone.
  YearGridState copyWith({
    int? year,
    List<MoodSeriesPoint>? points,
    bool? hasLoaded,
    Object? errorMessage = _unset,
  }) => YearGridState(
    year: year ?? this.year,
    points: points ?? this.points,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
  );
}

/// Holds the state behind the Year in Pixels grid.
///
/// Reads the whole calendar year in one request at day granularity — up to
/// 366 days, comfortably under the backend's 400-day cap on that
/// granularity (see `MAX_SERIES_RANGE_DAYS` in the backend's
/// `insights/constants.ts`) — rather than a request per month, so a switch
/// between years costs exactly one round trip. [InsightsApi.series] always
/// requests day granularity itself, so there is no granularity to choose
/// here.
class YearGridController extends Notifier<YearGridState> {
  @override
  YearGridState build() {
    final initial = CalendarDate.today(now: ref.watch(calendarNowProvider))
        .year;
    // Deferred a microtask for the same reason `CalendarController.build`
    // is: `build` has not returned yet, so touching `state` any earlier
    // would read from an uninitialized provider.
    unawaited(Future.microtask(() => _load(initial)));
    return YearGridState(year: initial);
  }

  Future<void> _load(int year) async {
    // Updates the year (and clears any stale error) synchronously, before
    // the request even starts, so the switcher label never lags behind a
    // tap — same as `CalendarController._load`.
    state = state.copyWith(year: year, errorMessage: null);
    try {
      final result = await ref
          .read(insightsApiProvider)
          .series(
            from: CalendarDate(year, 1, 1),
            to: CalendarDate(year, 12, 31),
          );
      if (!ref.mounted) return;
      state = state.copyWith(points: result.points, hasLoaded: true);
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(hasLoaded: true, errorMessage: error.message);
    }
  }

  /// The latest year the switcher will ever move to.
  int get _currentYear =>
      CalendarDate.today(now: ref.read(calendarNowProvider)).year;

  /// Shows the year before whichever one is on screen now.
  void previousYear() => unawaited(_load(state.year - 1));

  /// Shows the year after whichever one is on screen now — a no-op once
  /// that would move past [_currentYear], which is the forward clamp the
  /// year switcher's own disabled state mirrors.
  void nextYear() {
    final next = state.year + 1;
    if (next > _currentYear) return;
    unawaited(_load(next));
  }

  /// Clears the current error message once the screen has shown it.
  void dismissError() => state = state.copyWith(errorMessage: null);
}

/// The state behind the Year in Pixels grid.
final yearGridControllerProvider =
    NotifierProvider<YearGridController, YearGridState>(
      YearGridController.new,
    );
