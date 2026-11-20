import 'package:gapfinderfrontend_dart/data/local/miguel/study_mode_outbox.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/open_table_outbox.dart';

// Every text about queued actions, in one place (shown to the user, so in Spanish)
class OutboxMessages {
  // Only these actions are announced when they are sent; stats like app_session stay silent
  static const announcedTypes = {
    OpenTableOutbox.joinType,
    OpenTableOutbox.leaveType,
    OpenTableOutbox.createType,
  };

  static bool isAnnounced(String type) => announcedTypes.contains(type);

  // What a pending action is, for the logout warning (null = silent stat, not listed)
  static String? pending(String type, String? label) {
    final name = label == null ? '' : ' «$label»';
    switch (type) {
      case OpenTableOutbox.createType:
        return 'Publicar la mesa$name';
      case OpenTableOutbox.joinType:
        return 'Unirte a la mesa$name';
      case OpenTableOutbox.leaveType:
        return 'Salir de la mesa$name';
      case 'chat_message':
        return label == null ? 'Enviar un mensaje de chat' : 'Enviar un mensaje a $label';
      case 'friend_request_send':
        return 'Enviar una solicitud de amistad';
      case 'friend_request_accept':
        return 'Aceptar una solicitud de amistad';
      case 'friend_request_reject':
        return 'Rechazar una solicitud de amistad';
      case 'match_connect':
        return 'Conectar con tu match';
      case 'match_invitation_accept':
        return 'Aceptar una invitación';
      case 'match_invitation_decline':
        return 'Rechazar una invitación';
      case 'match_rating':
        return label == null ? 'Calificar tu match' : 'Calificar tu match con $label';
      case 'user_interests_save':
        return 'Guardar tus intereses';
      case StudyModeOutbox.addType:
        return 'Activar el modo estudio';
      case StudyModeOutbox.removeType:
        return 'Quitar un periodo de modo estudio';
      default:
        return null;
    }
  }

  // Text when the action reached the back
  static String delivered(String type, String label) {
    switch (type) {
      case OpenTableOutbox.createType:
        return 'Volvió la conexión: tu mesa «$label» ya está publicada';
      case OpenTableOutbox.joinType:
        return 'Volvió la conexión: ya te uniste a la mesa «$label»';
      case OpenTableOutbox.leaveType:
        return 'Volvió la conexión: saliste de la mesa «$label»';
      default:
        return 'Volvió la conexión: se envió «$label»';
    }
  }

  // Text when the back refused the action
  static String refused(String type, String label, String reason) {
    switch (type) {
      case OpenTableOutbox.createType:
        return 'No pudimos publicar tu mesa «$label»: $reason';
      case OpenTableOutbox.joinType:
        return 'No te pudimos unir a la mesa «$label»: $reason';
      case OpenTableOutbox.leaveType:
        return 'No pudimos sacarte de la mesa «$label»: $reason';
      default:
        return 'No se pudo enviar «$label»: $reason';
    }
  }

  // Dialog after queueing a join / leave / new table
  static const joinQueuedTitle = 'Solicitud enviada';
  static const joinQueuedBody =
      'Tu solicitud para unirte quedó guardada. Se enviará sola cuando vuelva el internet y te avisaremos.';
  static const leaveQueuedTitle = 'Solicitud enviada';
  static const leaveQueuedBody =
      'Tu salida de la mesa quedó guardada. Se enviará sola cuando vuelva el internet y te avisaremos.';
  static const createQueuedTitle = 'Mesa enviada';
  static const createQueuedBody =
      'Tu mesa quedó guardada. Se publicará sola cuando vuelva el internet y te avisaremos.';

  // Hint under Publish when there is no connection
  static const publishOfflineHint = 'Sin conexión: tu mesa se guardará y se publicará cuando vuelva el internet';
}
