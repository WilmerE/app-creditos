abstract final class DateHelpers {
  static DateTime mondayOf(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day - (date.weekday - DateTime.monday),
    );
  }

  static bool isSaturday(DateTime date) => date.weekday == DateTime.saturday;
}
