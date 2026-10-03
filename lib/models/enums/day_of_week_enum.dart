enum DayOfWeekEnum {
  MON,
  TUE,
  WED,
  THU,
  FRI,
  SAT,
  SUN;

  static DayOfWeekEnum fromString(String day) {
    return DayOfWeekEnum.values.firstWhere(
      (e) => e.name == day.toUpperCase(),
      orElse: () => DayOfWeekEnum.MON,
    );
  }

  String toJson() => name;
}
