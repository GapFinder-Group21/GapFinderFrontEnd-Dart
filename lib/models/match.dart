import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/core/utils/date_formatter_util.dart';

class Match {
  // MatchBasicDTO
  final int id;
  final DateTime startTime;
  final DateTime endTime;
  final double? score;
  final MatchStatusEnum status;
  final int? proposerGapId;
  final int? acceptorGapId;

  // MatchCompleteDTO (con GapCompleteDTO, cada gap trae su user)
  final Gap? proposerGap;
  final Gap? acceptorGap;

  Match({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.score,
    required this.status,
    this.proposerGapId,
    this.acceptorGapId,
    this.proposerGap,
    this.acceptorGap,
  });

  int get durationMinutes => endTime.difference(startTime).inMinutes;

  factory Match.fromJson(Map<String, dynamic> json) {
    final proposerGap = json['proposerGap'] != null
        ? Gap.fromJson(json['proposerGap'])
        : null;
    final acceptorGap = json['acceptorGap'] != null
        ? Gap.fromJson(json['acceptorGap'])
        : null;

    return Match(
      id: json['id'],
      startTime: DateFormatterUtil.parseDateTime(json['startTime']),
      endTime: DateFormatterUtil.parseDateTime(json['endTime']),
      score: (json['score'] as num?)?.toDouble(),
      status: MatchStatusEnum.fromString(json['status']),
      // El id plano viene en MatchBasicDTO; si solo llega el gap completo, se toma de ahí
      proposerGapId: json['proposerGapId'] ?? proposerGap?.id,
      acceptorGapId: json['acceptorGapId'] ?? acceptorGap?.id,
      proposerGap: proposerGap,
      acceptorGap: acceptorGap,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': DateFormatterUtil.formatDateTime(startTime),
    'endTime': DateFormatterUtil.formatDateTime(endTime),
    'score': score,
    'status': status.toJson(),
    'proposerGapId': proposerGapId,
    'acceptorGapId': acceptorGapId,
  };
}
