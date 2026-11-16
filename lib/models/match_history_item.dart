import 'package:gapfinderfrontend_dart/core/utils/date_formatter_util.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';

// A rating inside the match history (MatchRatingDTO)
class MatchRating {
  // From 1 to 5
  final int stars;
  final String? comment;
  // null while the rating is still waiting in the outbox (the back did not store it yet)
  final DateTime? createdAt;

  const MatchRating({required this.stars, this.comment, this.createdAt});

  factory MatchRating.fromJson(Map<String, dynamic> json) {
    return MatchRating(
      stars: (json['stars'] as num).toInt(),
      comment: json['comment'] as String?,
      createdAt: json['createdAt'] != null ? DateFormatterUtil.parseDateTime(json['createdAt']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'stars': stars,
        'comment': comment,
        'createdAt': createdAt != null ? DateFormatterUtil.formatDateTime(createdAt!) : null,
      };
}

// One match of the "Mis matches" view, seen by the logged user (MatchHistoryItemDTO)
class MatchHistoryItem {
  final int matchId;
  final MatchStatusEnum status;
  final DateTime startTime;
  final DateTime endTime;
  final double? score;
  // The other student of the match
  final User? otherUser;
  // My rating, null if I have not rated yet
  final MatchRating? myRating;
  // The rating of the other student. The back keeps it null until I rate, even if they already did
  final MatchRating? otherRating;
  // True when the match is COMPLETED and I have not rated it
  final bool canRate;

  const MatchHistoryItem({
    required this.matchId,
    required this.status,
    required this.startTime,
    required this.endTime,
    this.score,
    this.otherUser,
    this.myRating,
    this.otherRating,
    this.canRate = false,
  });

  bool get isCompleted => status == MatchStatusEnum.COMPLETED;

  factory MatchHistoryItem.fromJson(Map<String, dynamic> json) {
    return MatchHistoryItem(
      matchId: (json['matchId'] as num).toInt(),
      status: MatchStatusEnum.fromString(json['status'] as String? ?? ''),
      startTime: DateFormatterUtil.parseDateTime(json['startTime']),
      endTime: DateFormatterUtil.parseDateTime(json['endTime']),
      score: (json['score'] as num?)?.toDouble(),
      otherUser: json['otherUser'] != null ? User.fromJson(Map<String, dynamic>.from(json['otherUser'])) : null,
      myRating: json['myRating'] != null ? MatchRating.fromJson(Map<String, dynamic>.from(json['myRating'])) : null,
      otherRating:
          json['otherRating'] != null ? MatchRating.fromJson(Map<String, dynamic>.from(json['otherRating'])) : null,
      canRate: json['canRate'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'matchId': matchId,
        'status': status.toJson(),
        'startTime': DateFormatterUtil.formatDateTime(startTime),
        'endTime': DateFormatterUtil.formatDateTime(endTime),
        'score': score,
        'otherUser': otherUser?.toJson(),
        'myRating': myRating?.toJson(),
        'otherRating': otherRating?.toJson(),
        'canRate': canRate,
      };

  // The same match with my rating (used for the optimistic rating that waits in the outbox)
  MatchHistoryItem withMyRating(MatchRating rating) => MatchHistoryItem(
        matchId: matchId,
        status: status,
        startTime: startTime,
        endTime: endTime,
        score: score,
        otherUser: otherUser,
        myRating: rating,
        otherRating: otherRating,
        canRate: false,
      );
}
