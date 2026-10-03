enum OpenTableStatusEnum {
  OPEN,
  FULL,
  COMPLETED,
  EMPTY;

  static OpenTableStatusEnum fromString(String status) {
    return OpenTableStatusEnum.values.firstWhere(
          (value) => value.name == status.toUpperCase(),
      orElse: () => OpenTableStatusEnum.OPEN,
    );
  }

  String toJson() => name;
}
