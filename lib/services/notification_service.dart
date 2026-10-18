import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/models/app_notification.dart';

class NotificationService {
  // All notifications of a user - GET /api/notifications/user/{userId}
  Future<List<AppNotification>> getNotificationsByUser(int userId) async {
    final res = await ApiClient.get('/api/notifications/user/$userId');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting notifications'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => AppNotification.fromJson(json)).toList();
  }

  // Get unread notifications of a user - GET /api/notifications/user/{userId}/unread
  Future<List<AppNotification>> getUnreadByUser(int userId) async {
    final res = await ApiClient.get('/api/notifications/user/$userId/unread');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting unread notifications'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => AppNotification.fromJson(json)).toList();
  }

  // Mark one notification as read - PUT /api/notifications/{notificationId}/read?userId={userId}
  Future<AppNotification> markAsRead(int notificationId, int userId) async {
    final res = await ApiClient.put(
      '/api/notifications/$notificationId/read?userId=$userId',
    );

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error marking notification as read'));
    }

    return AppNotification.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Mark all unread notifications of a user as read - PUT /api/notifications/user/{userId}/read-all
  Future<void> markAllAsRead(int userId) async {
    final res = await ApiClient.put('/api/notifications/user/$userId/read-all');

    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error marking all as read'));
    }
  }

  // The back sends errors as plain text (400/403/404/409) or as JSON {"error": "..."} (409)
  String _errorMessage(dynamic res, String fallback) {
    final body = utf8.decode(res.bodyBytes).trim();
    if (body.isEmpty) return '$fallback: ${res.statusCode}';

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      // Not JSON, it is plain text
    }
    return body;
  }
}
