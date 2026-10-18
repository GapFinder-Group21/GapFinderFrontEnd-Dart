import 'package:flutter/material.dart' show TimeOfDay;

// Text formatters shared by the views (they only turn values into text)
class DisplayFormatters {
  // TimeOfDay -> "8:00" / "2:30" (12h format without AM/PM)
  static String timeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // DateTime -> "9:30" (12h format without AM/PM)
  static String time(DateTime time) => timeOfDay(TimeOfDay.fromDateTime(time));

  // Minutes -> "1h 30m free" / "45m free"
  static String freeDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m free';
    if (h > 0) return '${h}h free';
    return '${m}m free';
  }

  // Date and time, e.g. "Mon, Oct 6 - 9:30"
  static String fullDateTime(DateTime dt) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    final day = weekdays[dt.weekday - 1];
    final month = months[dt.month - 1];
    final time = "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";

    return "$day, $month ${dt.day} - $time";
  }

  // Gets the text of an interest, whatever type it comes as
  static String interest(dynamic interest) {
    if (interest is String) return interest;
    try {
      return interest.name ?? '';
    } catch (_) {
      return interest.toString();
    }
  }
}
