import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/core/storage/local_file_store.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/outbox_keys.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/pending_photo_store.dart';

// Publishing an open table is a multipart request (JSON + photo), not a simple JSON request,
// so the outbox cannot send it alone: this handler does it.
// The queued row body is {"openTable": <the same map sent to the back>, "photoPath": "pending_photos/x.jpg"}
// and its dedupe key is photo_upload:<photoPath>, so the same photo is uploaded only once.
class PhotoUploadOutbox {
  static const endpoint = '/open-tables';

  // Connects the handler to the outbox (called from registerOutboxHandlers)
  static void register({OutboxService? outbox}) {
    (outbox ?? OutboxService.instance).registerHandler(OutboxTypes.photoUpload, _upload);
  }

  // Queues the upload of a photo already copied to pending_photos/
  static Future<bool> enqueue({
    required Map<String, dynamic> openTable,
    required String photoPath,
    OutboxService? outbox,
  }) {
    return (outbox ?? OutboxService.instance).enqueue(
      type: OutboxTypes.photoUpload,
      method: 'POST',
      endpoint: endpoint,
      body: {'openTable': openTable, 'photoPath': photoPath},
      dedupeKey: OutboxKeys.photoUpload(photoPath),
    );
  }

  // Returns true when the table was created (the outbox then deletes the row)
  static Future<bool> _upload(Map<String, dynamic> row) async {
    final body = jsonDecode(row['body'] as String) as Map<String, dynamic>;
    final photoPath = body['photoPath'] as String;

    final bytes = await LocalFileStore.instance.readBytes(photoPath);
    if (bytes == null) throw Exception('The pending photo does not exist anymore: $photoPath');

    final res = await ApiClient.postMultipart(
      endpoint,
      files: () async => [
        http.MultipartFile.fromString(
          'openTable',
          jsonEncode(body['openTable']),
          contentType: MediaType('application', 'json'),
        ),
        http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: 'photo.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      ],
    );

    if (res.statusCode != 201) return false;

    // The table is published: the local copy is not needed anymore
    try {
      final pending = PendingPhotoStore();
      if (await pending.currentPath() == photoPath) {
        await pending.clear();
      } else {
        await LocalFileStore.instance.delete(photoPath);
      }
    } catch (e) {
      debugPrint('Could not remove the uploaded photo: $e');
    }
    return true;
  }
}
