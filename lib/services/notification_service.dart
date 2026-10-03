import 'dart:convert';
import '../core/api_client.dart';
import '../models/app_notification.dart';

class NotificationService {
  // All notifications of a user - GET /api/notifications/user/{userId}
  Future<List<AppNotification>> getNotificationsByUser(int userId) async {
    final res = await ApiClient.get('/api/notifications/user/$userId');

    if (res.statusCode != 200) {
      throw Exception('Error getting notifications: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => AppNotification.fromJson(json)).toList();
  }

  // Get unread notifications of a user - GET /api/notifications/user/{userId}/unread
  Future<List<AppNotification>> getUnreadByUser(int userId) async {
    final res = await ApiClient.get('/api/notifications/user/$userId/unread');

    if (res.statusCode != 200) {
      throw Exception('Error getting unread notifications: ${res.statusCode}');
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
      throw Exception('Error marking notification as read: ${res.statusCode}');
    }

    return AppNotification.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Mark all unread notifications of a user as read - PUT /api/notifications/user/{userId}/read-all
  Future<void> markAllAsRead(int userId) async {
    final res = await ApiClient.put('/api/notifications/user/$userId/read-all');

    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception('Error marking all as read: ${res.statusCode}');
    }
  }
}
