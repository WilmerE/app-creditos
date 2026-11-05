abstract final class DateHelpers {
  static DateTime mondayOf(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day - (date.weekday - DateTime.monday),
    );
  }

  static bool isSaturday(DateTime date) => date.weekday == DateTime.saturday;

  /// First Monday strictly after [from] (time of day discarded).
  static DateTime nextMonday(DateTime from) {
    final days = (DateTime.monday - from.weekday + 7) % 7;
    return DateTime(from.year, from.month, from.day + (days == 0 ? 7 : days));
  }
}
