import 'package:gapfinderfrontend_dart/models/gap.dart';

class MatchCandidate {
  final Gap proposerGap;
  final Gap acceptorGap;
  final double score;

  MatchCandidate({
    required this.proposerGap,
    required this.acceptorGap,
    required this.score,
  });

  factory MatchCandidate.fromJson(Map<String, dynamic> json) {
    return MatchCandidate(
      proposerGap: Gap.fromJson(json['proposerGap']),
      acceptorGap: Gap.fromJson(json['acceptorGap']),
      score: (json['score'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'proposerGap': proposerGap.toJson(),
    'acceptorGap': acceptorGap.toJson(),
    'score': score,
  };
}
