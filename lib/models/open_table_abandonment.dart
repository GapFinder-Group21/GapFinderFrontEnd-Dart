// Pasos del formulario de creación de una Open Table.
// El backend los recibe como texto: ACTIVITY, DESCRIPTION, PARTICIPANTS, LOCATION.
enum OpenTableCreationStep {
  activity,
  description,
  participants,
  location;

  String toJson() => name.toUpperCase();

  static OpenTableCreationStep fromJson(String value) {
    return OpenTableCreationStep.values.firstWhere((step) => step.toJson() == value);
  }
}

// Abandono del formulario de creación: en qué paso se fue el usuario y lo que ya había elegido.
class OpenTableAbandonment {
  final int userId;
  final OpenTableCreationStep step;
  final int? activityId;
  final int? durationMinutes;
  final int? maxParticipants;
  final int? buildingId;

  OpenTableAbandonment({
    required this.userId,
    required this.step,
    this.activityId,
    this.durationMinutes,
    this.maxParticipants,
    this.buildingId,
  });

  // userId va en la ruta, no en el body
  Map<String, dynamic> toJson() => {
    'step': step.toJson(),
    'activityId': activityId,
    'durationMinutes': durationMinutes,
    'maxParticipants': maxParticipants,
    'buildingId': buildingId,
  };
}
