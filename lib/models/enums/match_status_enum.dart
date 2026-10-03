enum MatchStatusEnum {
  PENDING,
  ACCEPTED,
  REJECTED,
  COMPLETED;

  static MatchStatusEnum fromString(String value) {
    return MatchStatusEnum.values.firstWhere(
          (e) => e.name == value.toUpperCase(),
      orElse: () => MatchStatusEnum.PENDING,
    );
  }

  String toJson() => name;
}