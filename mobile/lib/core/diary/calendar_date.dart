/// A date on the calendar, with no time-of-day and no timezone.
///
/// Dart has no `LocalDate` of its own — [DateTime] always carries a clock
/// reading and a UTC/local flag. Every entry date, month boundary, and
/// "last occurrence" on the wire is a property of the calendar, never an
/// instant, so this value type fills that gap rather than pressing
/// [DateTime] into a role it was not built for.
class const CalendarDate(final int year, final int month, final int day)
    implements Comparable<CalendarDate> {
  static final RegExp _isoPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// Parses a wire `YYYY-MM-DD` date.
  ///
  /// Throws [FormatException] not just on the wrong shape but on a date that
  /// shape cannot mean — `2026-02-30` matches the pattern and is still
  /// nonsense, so this also checks the value round-trips through the
  /// calendar unchanged.
  factory CalendarDate.parse(String iso) {
    final match = _isoPattern.firstMatch(iso);
    if (match == null) {
      throw FormatException('Not a calendar date: $iso');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final normalized = DateTime(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw FormatException('Not a calendar date: $iso');
    }
    return CalendarDate(year, month, day);
  }

  /// The date [dateTime] falls on, dropping its time of day.
  factory CalendarDate.fromDateTime(DateTime dateTime) =>
      CalendarDate(dateTime.year, dateTime.month, dateTime.day);

  /// Today's date, on the clock given by [now] (or the real one).
  ///
  /// [now] exists so a caller can pin "today" in a test rather than reaching
  /// for a real clock.
  factory CalendarDate.today({DateTime? now}) =>
      CalendarDate.fromDateTime(now ?? DateTime.now());

  /// Parses [iso], returning null instead of throwing when it does not
  /// resolve to a real date.
  static CalendarDate? tryParse(String? iso) {
    if (iso == null) return null;
    try {
      return CalendarDate.parse(iso);
    } on FormatException {
      return null;
    }
  }

  /// This date at local midnight.
  DateTime toDateTime() => DateTime(year, month, day);

  /// 1 = Monday .. 7 = Sunday, matching [DateTime.weekday].
  int get weekday => toDateTime().weekday;

  /// The date [days] after this one, or before it for a negative count.
  CalendarDate addDays(int days) =>
      CalendarDate.fromDateTime(toDateTime().add(Duration(days: days)));

  @override
  int compareTo(CalendarDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  /// Whether this date falls before [other].
  bool operator <(CalendarDate other) => compareTo(other) < 0;

  /// Whether this date falls after [other].
  bool operator >(CalendarDate other) => compareTo(other) > 0;

  /// Whether this date falls on or before [other].
  bool operator <=(CalendarDate other) => compareTo(other) <= 0;

  /// Whether this date falls on or after [other].
  bool operator >=(CalendarDate other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is CalendarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

/// A calendar month, with no day of its own — the unit the monthly calendar
/// and the "when" insights bucket by.
class const YearMonth(final int year, final int month)
    implements Comparable<YearMonth> {
  static final RegExp _isoPattern = RegExp(r'^(\d{4})-(\d{2})$');

  /// Parses a wire `YYYY-MM` month.
  ///
  /// Throws [FormatException] on the wrong shape or a month number outside
  /// 1..12.
  factory YearMonth.parse(String iso) {
    final match = _isoPattern.firstMatch(iso);
    if (match == null) {
      throw FormatException('Not a year-month: $iso');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    if (month < 1 || month > 12) {
      throw FormatException('Not a year-month: $iso');
    }
    return YearMonth(year, month);
  }

  /// The month [date] falls in.
  factory YearMonth.fromDate(CalendarDate date) =>
      YearMonth(date.year, date.month);

  /// The current month, on the clock given by [now] (or the real one).
  factory YearMonth.current({DateTime? now}) =>
      YearMonth.fromDate(CalendarDate.today(now: now));

  /// Parses [iso], returning null instead of throwing when it does not
  /// resolve to a real month.
  static YearMonth? tryParse(String? iso) {
    if (iso == null) return null;
    try {
      return YearMonth.parse(iso);
    } on FormatException {
      return null;
    }
  }

  /// The month [months] after this one, or before it for a negative count.
  YearMonth addMonths(int months) {
    final total = year * 12 + (month - 1) + months;
    // Dart's `~/` truncates toward zero, which is wrong for a negative
    // total; floor division is what keeps December - 1 month landing in the
    // year before rather than wrapping to month 0.
    final newYear = total >= 0 ? total ~/ 12 : -((-total + 11) ~/ 12);
    final newMonth = total - newYear * 12 + 1;
    return YearMonth(newYear, newMonth);
  }

  /// How many days this month has, leap years included.
  int get lengthInDays => DateTime(year, month + 1, 0).day;

  /// The first day of this month.
  CalendarDate get firstDay => CalendarDate(year, month, 1);

  /// The last day of this month.
  CalendarDate get lastDay => CalendarDate(year, month, lengthInDays);

  @override
  int compareTo(YearMonth other) {
    if (year != other.year) return year.compareTo(other.year);
    return month.compareTo(other.month);
  }

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
}
