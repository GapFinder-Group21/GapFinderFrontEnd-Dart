enum FriendshipStatusEnum {
  pending,
  accepted,
  rejected;

  static FriendshipStatusEnum fromString(String status) {
    return FriendshipStatusEnum.values.firstWhere(
          (e) => e.name.toUpperCase() == status.toUpperCase(),
      orElse: () => FriendshipStatusEnum.pending,
    );
  }

  // El back espera PENDING, ACCEPTED, REJECTED
  String toJson() => name.toUpperCase();
}