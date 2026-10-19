import 'package:gapfinderfrontend_dart/data/local/joel/photo_upload_outbox.dart';

// Registers the handlers of the actions that are not a simple JSON request
// (for example uploading a photo). See OutboxService.registerHandler.
void registerOutboxHandlers() {
  // Cada integrante registra aquí sus handlers
  PhotoUploadOutbox.register();
}
