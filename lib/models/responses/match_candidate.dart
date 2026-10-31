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

  // There is no toJson on purpose: Gap.toJson is the request body and leaves out the nested user (name, avatar).
  // To save a candidate on the device use SeenCandidatesDao, which writes both gaps with gapCacheJson.
}
