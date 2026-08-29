import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diary/calendar_date.dart';
import '../../core/diary/diary_providers.dart';
import '../../core/diary/monthly_summary.dart';
import '../../core/network/api_error.dart';

/// The clock a freshly built [CalendarController] reads "the current month"
/// against.
///
/// Overridden in tests so the month a controller opens on is deterministic
/// rather than following the real device clock — the same reason
/// [CalendarDate.today] itself takes an injectable `now`.
final calendarNowProvider = Provider<DateTime?>((ref) => null);

/// The calendar screen's state: the month currently shown, its summary once
/// loaded, and the most recent failure that has not yet been shown.
///
/// [summary] stays null until the first fetch for whichever month is
/// current succeeds, and is left untouched by a failed later fetch. See
/// [CalendarController]. [hasLoaded] is what gates the spinner ([summary]
/// alone cannot: it also reads null after a failed first load, and the
/// screen must not spin forever over that).
class const CalendarState({
  required final YearMonth month,
  final MonthlySummary? summary,
  final bool hasLoaded = false,
  final String? errorMessage,
}) {
  /// Distinguishes "leave [errorMessage] alone" from "clear it" in
  /// [copyWith] — a plain `errorMessage ?? this.errorMessage` can never null
  /// the field back out once set.
  static const Object _unset = Object();

  /// A copy of this state with the given fields replaced.
  ///
  /// Pass `errorMessage: null` to explicitly clear it; omit it to leave the
  /// current value alone.
  CalendarState copyWith({
    YearMonth? month,
    MonthlySummary? summary,
    bool? hasLoaded,
    Object? errorMessage = _unset,
  }) => CalendarState(
    month: month ?? this.month,
    summary: summary ?? this.summary,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
  );
}

/// Holds the state behind the monthly calendar screen.
///
/// Switching months keeps whatever summary is already on screen while the
/// new one loads instead of blanking the grid: once the first month has
/// loaded, later navigation never flashes a spinner over content the user
/// is already reading — [CalendarState.hasLoaded] never goes back to false.
class CalendarController extends Notifier<CalendarState> {
  @override
  CalendarState build() {
    final initial = YearMonth.current(now: ref.watch(calendarNowProvider));
    // Deferred a microtask: `build` has not returned yet, so Riverpod has
    // not stored this notifier's initial state, and `_load` touching
    // `state` any earlier than this would read from an uninitialized
    // provider.
    unawaited(Future.microtask(() => _load(initial)));
    return CalendarState(month: initial);
  }

  Future<void> _load(YearMonth month) async {
    // Updates the month (and clears any stale error) synchronously, before
    // the request even starts, so the switcher label and any already-loaded
    // grid never lag behind a tap.
    state = state.copyWith(month: month, errorMessage: null);
    try {
      final summary = await ref.read(monthlySummaryApiProvider).forMonth(month);
      if (!ref.mounted) return;
      state = state.copyWith(summary: summary, hasLoaded: true);
    } on ApiError catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(hasLoaded: true, errorMessage: error.message);
    }
  }

  /// Shows the month before whichever one is on screen now.
  void previousMonth() => unawaited(_load(state.month.addMonths(-1)));

  /// Shows the month after whichever one is on screen now.
  void nextMonth() => unawaited(_load(state.month.addMonths(1)));

  /// Reloads whichever month is on screen right now.
  ///
  /// Called on `AppLifecycleState.resumed`. Reads [state] live rather than
  /// closing over a month captured at some earlier point, so a resume
  /// reloads the month actually showing even when the user has since
  /// navigated away from whichever one was current when the screen first
  /// opened.
  Future<void> reloadCurrentMonth() => _load(state.month);

  /// Clears the current error message once the screen has shown it, so a
  /// rebuild does not show the same `SnackBar` again.
  void dismissError() => state = state.copyWith(errorMessage: null);
}

/// The state behind the monthly calendar screen.
final calendarControllerProvider =
    NotifierProvider<CalendarController, CalendarState>(
      CalendarController.new,
    );
