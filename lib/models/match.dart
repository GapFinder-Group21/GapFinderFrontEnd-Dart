import 'gap.dart';
import 'match_status_enum.dart';
import '../utils/date_formatter_util.dart';

class Match {
  // MatchBasicDTO
  final int id;
  final DateTime startTime;
  final DateTime endTime;
  final double? score;
  final MatchStatusEnum status;

  // MatchCompleteDTO (con GapCompleteDTO, cada gap trae su user)
  final Gap? proposerGap;
  final Gap? acceptorGap;

  Match({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.score,
    required this.status,
    this.proposerGap,
    this.acceptorGap,
  });

  int get durationMinutes => endTime.difference(startTime).inMinutes;

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      id: json['id'],
      startTime: DateFormatterUtil.parseDateTime(json['startTime']),
      endTime: DateFormatterUtil.parseDateTime(json['endTime']),
      score: (json['score'] as num?)?.toDouble(),
      status: MatchStatusEnum.fromString(json['status']),
      proposerGap: json['proposerGap'] != null
          ? Gap.fromJson(json['proposerGap'])
          : null,
      acceptorGap: json['acceptorGap'] != null
          ? Gap.fromJson(json['acceptorGap'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': DateFormatterUtil.formatDateTime(startTime),
    'endTime': DateFormatterUtil.formatDateTime(endTime),
    'score': score,
    'status': status.toJson(),
  };
}