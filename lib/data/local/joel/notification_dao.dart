import 'package:gapfinderfrontend_dart/data/local/joel/cache_json.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/json_row_dao.dart';
import 'package:gapfinderfrontend_dart/models/app_notification.dart';

// Notifications of the user (table notifications)
class NotificationDao extends JsonRowDao<AppNotification> {
  NotificationDao({super.database}) : super('notifications');

  @override
  int idOf(AppNotification item) => item.id;

  @override
  Map<String, dynamic> toJson(AppNotification item) => notificationCacheJson(item);

  @override
  AppNotification fromJson(Map<String, dynamic> json) => AppNotification.fromJson(json);

  @override
  Map<String, Object?> extraColumns(AppNotification item) => {'is_read': item.read ? 1 : 0};
}
