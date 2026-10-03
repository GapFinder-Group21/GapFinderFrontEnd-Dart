import 'dart:convert';
import '../core/api_client.dart';
import '../models/message.dart';

class MessageService {
  // Sends a match or open table message - POST /messages?senderId=...&matchId=...&openTableId=...&content=...
  Future<Message> sendMessage({
    required int senderId,
    int? matchId,
    int? openTableId,
    required String content,
  }) async {
    final queryParams = <String>[
      'senderId=$senderId',
      if (matchId != null) 'matchId=$matchId',
      if (openTableId != null) 'openTableId=$openTableId',
      'content=${Uri.encodeComponent(content)}',
    ];
    final res = await ApiClient.post('/messages?${queryParams.join('&')}');

    if (res.statusCode != 201) {
      throw Exception('Error sending message: ${res.statusCode}');
    }

    return Message.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Gets all messages from a match - GET /messages/match/{matchId}
  Future<List<Message>> getMessagesByMatch(int matchId) async {
    final res = await ApiClient.get('/messages/match/$matchId');

    if (res.statusCode != 200) {
      throw Exception('Error getting match messages: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => Message.fromJson(json)).toList();
  }

  // Gets all messages from an open table - GET /messages/opentable/{openTableId}
  Future<List<Message>> getMessagesByOpenTable(int openTableId) async {
    final res = await ApiClient.get('/messages/opentable/$openTableId');

    if (res.statusCode != 200) {
      throw Exception('Error getting open table messages: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => Message.fromJson(json)).toList();
  }

  // Gets a message by id - GET /messages/{id}
  Future<Message> getMessage(int id) async {
    final res = await ApiClient.get('/messages/$id');

    if (res.statusCode != 200) {
      throw Exception('Error getting message: ${res.statusCode}');
    }

    return Message.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }
}
