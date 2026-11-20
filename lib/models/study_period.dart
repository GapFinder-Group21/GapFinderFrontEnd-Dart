// How long the study mode lasts when the user turns it on ("Estoy estudiando ahora")
enum StudyDuration {
  thirtyMinutes(30, '30 min'),
  oneHour(60, '1 h'),
  // Until the gap the user is in ends (0 minutes: the length is the gap, not a number)
  untilGapEnds(0, 'Hasta que termine el gap');

  final int minutes;
  final String label;
  const StudyDuration(this.minutes, this.label);

  // The value saved in SharedPreferences (study_default_minutes:<userId>) is the minutes
  static StudyDuration? fromMinutes(int? minutes) {
    for (final duration in values) {
      if (duration.minutes == minutes) return duration;
    }
    return null;
  }
}

// A period in which the user is studying. While it lasts the back hides them from the match candidates
// and from the nearby friends. It is saved by time, not as a flag on the gap, so it still works when the
// gaps of the week are regenerated.
class StudyPeriod {
  // The longest period the back accepts
  static const maxDuration = Duration(hours: 12);

  // Id made on the phone (UUID): a retried request is never stored twice by the back
  final String clientId;
  // Id given by the back (null until it received the period)
  final int? serverId;
  final int userId;
  final DateTime startTime;
  final DateTime endTime;
  // The gap the user chose to hide (informational only, the back never uses it to filter)
  final int? gapId;
  // True when the back already has it, false while it waits in the outbox
  final bool synced;

  const StudyPeriod({
    required this.clientId,
    required this.userId,
    required this.startTime,
    required this.endTime,
    this.serverId,
    this.gapId,
    this.synced = false,
  });

  // StudyPeriodDTO of the back: {id, userId, startTime, endTime, gapId, clientId, createdAt}
  factory StudyPeriod.fromServer(Map<String, dynamic> json) {
    return StudyPeriod(
      clientId: json['clientId'] as String,
      serverId: (json['id'] as num?)?.toInt(),
      userId: (json['userId'] as num).toInt(),
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      gapId: (json['gapId'] as num?)?.toInt(),
      synced: true,
    );
  }

  // The period is going on at this moment
  bool isActiveAt(DateTime now) => !startTime.isAfter(now) && endTime.isAfter(now);

  bool hasEndedAt(DateTime now) => !endTime.isAfter(now);

  // True when the period shares time with the range [start, end)
  bool crosses(DateTime start, DateTime end) => startTime.isBefore(end) && endTime.isAfter(start);

  // The back reads LocalDateTime: local date and time without zone and without fractions of a second
  static String wireTime(DateTime time) {
    final text = time.toLocal().toIso8601String();
    return text.length > 19 ? text.substring(0, 19) : text;
  }

  // Body of POST /users/{userId}/study-mode
  Map<String, dynamic> toCreateBody() => {
        'startTime': wireTime(startTime),
        'endTime': wireTime(endTime),
        'gapId': gapId,
        'clientId': clientId,
      };

  StudyPeriod copyWith({int? serverId, bool? synced}) {
    return StudyPeriod(
      clientId: clientId,
      userId: userId,
      startTime: startTime,
      endTime: endTime,
      serverId: serverId ?? this.serverId,
      gapId: gapId,
      synced: synced ?? this.synced,
    );
  }

  @override
  String toString() => 'StudyPeriod($clientId, $startTime - $endTime, synced: $synced)';
}
