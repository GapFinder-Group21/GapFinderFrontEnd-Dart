enum NotificationTypeEnum {
  FRIEND_REQUEST_SENT,
  FRIEND_REQUEST_ACCEPTED,
  FRIEND_REQUEST_REJECTED,
  MATCH_PROPOSED,
  MATCH_ACCEPTED,
  MATCH_REJECTED,
  OPEN_TABLE_JOINED;

  static NotificationTypeEnum fromString(String value) {
    return NotificationTypeEnum.values.firstWhere(
          (e) => e.name == value.toUpperCase(),
      orElse: () => NotificationTypeEnum.FRIEND_REQUEST_SENT,
    );
  }

  String toJson() => name;
}