import 'dart:io';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/app_notification.dart';
import 'package:gapfinderfrontend_dart/models/friendship.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';

// Local cache that saves and reads nothing, so the view model tests do not need SQLite or Hive
class NoopLocalCache extends JoelLocalCache {
  @override
  void saveFriends(int userId, List<User> list, List<Friendship> requests) {}

  @override
  void saveNotifications(int userId, List<AppNotification> list) {}

  @override
  void saveMatches(int userId, List<Match> list, Set<int> userGapIds) {}

  @override
  void saveInvitationMatch(Match match) {}

  @override
  void saveGaps(int userId, List<Gap> list) {}

  @override
  void saveMatchOfUser(int userId, Match match) {}

  @override
  void saveProfile(Future<User> Function() load, User fallback) {}

  @override
  void saveMainTab(int tabIndex) {}

  @override
  void savePendingPhoto(File photo) {}

  @override
  void clearPendingPhoto() {}

  @override
  Future<T?> safeRead<T>(String what, Future<T?> Function() read) async => null;
}
