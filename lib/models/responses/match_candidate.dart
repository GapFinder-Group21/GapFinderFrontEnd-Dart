import '../gap.dart';

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
}
