import 'package:gapfinderfrontend_dart/data/local/miguel/study_mode_outbox.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/user_interests_outbox.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/open_table_outbox.dart';

// Registers the handlers of the actions that are not a simple JSON request
// (for example saving the interests, which is several requests). See OutboxService.registerHandler.
void registerOutboxHandlers() {
  // Cada integrante registra aquí sus handlers
  UserInterestsOutbox.register();
  StudyModeOutbox.register();
  OpenTableOutbox.register();
}
