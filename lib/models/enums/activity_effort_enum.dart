enum ActivityEffortEnum {
  QUIET,
  NORMAL,
  ACTIVE;

  static ActivityEffortEnum fromString(String effort) {
    return ActivityEffortEnum.values.firstWhere(
      (e) => e.name == effort.toUpperCase(),
      orElse: () => ActivityEffortEnum.NORMAL,
    );
  }

  String toJson() => name;
}
