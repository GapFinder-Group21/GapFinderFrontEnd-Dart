enum MatchModeEnum {
  career,
  interests,
  effort;

  static MatchModeEnum fromString(String value) {
    return MatchModeEnum.values.firstWhere(
          (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => MatchModeEnum.career,
    );
  }

  String toJson() => name.toUpperCase();
}
