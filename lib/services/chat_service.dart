import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/models/chat_message.dart';

// The back refused the message for good (not friends 422, empty or too long 400)
class ChatRefusedException implements Exception {
  final String message;
  ChatRefusedException(this.message);

  @override
  String toString() => message;
}

class ChatService {
  // Messages with a friend newer than afterId (oldest first, max 50) - GET /chats/user/{userId}/with/{friendId}
  // Returns the raw JSON text: it is parsed in an isolate, not here
  Future<String> getConversationBody(int userId, int friendId, {int afterId = 0}) async {
    final res = await ApiClient.get('/chats/user/$userId/with/$friendId?afterId=$afterId');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'No pudimos cargar el chat'));
    }
    return utf8.decode(res.bodyBytes);
  }

  // Sends a message - POST /chats/messages {receiverId, content, clientId}
  // Returns the stored message, or null on 409 (it was already sent: the back has it)
  Future<ChatMessage?> send(int receiverId, String content, String clientId) async {
    final res = await ApiClient.post('/chats/messages', body: {
      'receiverId': receiverId,
      'content': content,
      'clientId': clientId,
    });

    if (res.statusCode == 201 || res.statusCode == 200) {
      return ChatMessage.fromServer(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    }
    if (res.statusCode == 409) return null;
    if (res.statusCode == 400 || res.statusCode == 422) {
      throw ChatRefusedException(_errorMessage(res, 'No se pudo enviar el mensaje'));
    }
    throw Exception(_errorMessage(res, 'No se pudo enviar el mensaje'));
  }

  // The back sends errors as plain text or as JSON {"error": "..."}
  String _errorMessage(dynamic res, String fallback) {
    final body = utf8.decode(res.bodyBytes).trim();
    if (body.isEmpty) return fallback;

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && (decoded['error'] ?? decoded['message']) != null) {
        return plainBackendText((decoded['error'] ?? decoded['message']).toString(), fallback);
      }
    } catch (_) {
      // Not JSON, it is plain text
    }
    return plainBackendText(body, fallback);
  }
}
