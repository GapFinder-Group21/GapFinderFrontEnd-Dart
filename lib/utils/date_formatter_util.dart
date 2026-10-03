class DateFormatterUtil {
  static DateTime parseDateTime(String dateStr) {
    return DateTime.parse(dateStr);
  }

  static String formatDateTime(DateTime dateTime) {
    return dateTime.toIso8601String();
  }
}
