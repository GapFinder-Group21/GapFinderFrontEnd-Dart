enum EffortTypeEnum {
  LOW,
  MEDIUM,
  HIGH;

  static EffortTypeEnum fromString(String value) {
    return EffortTypeEnum.values.firstWhere(
          (e) => e.name == value.toUpperCase(),
      orElse: () => EffortTypeEnum.MEDIUM,
    );
  }

  String toJson() => name;
}