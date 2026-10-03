import 'package:flutter/material.dart';
import 'day_of_week_enum.dart';
import 'user.dart';
import '../utils/time_formatter_util.dart';

class ClassBlock {
  final int id;
  final String subject;
  final String location;
  final DayOfWeekEnum dayOfWeek;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final User? user;

  ClassBlock({
    required this.id,
    required this.subject,
    required this.location,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.user,
  });

  factory ClassBlock.fromJson(Map json) {
    return ClassBlock(
      id: json['id'],
      subject: json['subject'] ?? '',
      location: json['location'] ?? '',
      dayOfWeek: DayOfWeekEnum.fromString(json['dayOfWeek']),
      startTime: TimeFormatterUtil.parseTime(json['startTime']),
      endTime: TimeFormatterUtil.parseTime(json['endTime']),
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }

  Map toJson() {
    return {
      'id': id,
      'subject': subject,
      'location': location,
      'dayOfWeek': dayOfWeek.toJson(),
      'startTime': TimeFormatterUtil.formatTime(startTime),
      'endTime': TimeFormatterUtil.formatTime(endTime),
      'user': user?.toJson(),
    };
  }
}