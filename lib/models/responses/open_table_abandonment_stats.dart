import '../open_table_abandonment.dart';

// Estadística de abandono de un paso del formulario.
class OpenTableAbandonmentStats {
  final OpenTableCreationStep step;
  final int abandonments;
  final int reached;
  final double abandonmentRate; // entre 0 y 1

  OpenTableAbandonmentStats({
    required this.step,
    required this.abandonments,
    required this.reached,
    required this.abandonmentRate,
  });

  factory OpenTableAbandonmentStats.fromJson(Map<String, dynamic> json) {
    return OpenTableAbandonmentStats(
      step: OpenTableCreationStep.fromJson(json['step']),
      abandonments: json['abandonments'],
      reached: json['reached'],
      abandonmentRate: (json['abandonmentRate'] as num).toDouble(),
    );
  }
}
