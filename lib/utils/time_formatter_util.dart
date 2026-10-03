import 'package:flutter/material.dart';

class TimeFormatterUtil {
  /// Convierte un String "HH:mm:ss" o "HH:mm" a TimeOfDay
  static TimeOfDay parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  /// Convierte un TimeOfDay a String "HH:mm:ss" para el backend
  static String formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }
}
