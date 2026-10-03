enum ResponseStatusEnum {
  IN,
  OUT,
  PENDING;

  static ResponseStatusEnum fromString(String status) {
    return ResponseStatusEnum.values.firstWhere(
      (e) => e.name == status.toUpperCase(),
      orElse: () => ResponseStatusEnum.PENDING,
    );
  }

  String toJson() => name;
}
