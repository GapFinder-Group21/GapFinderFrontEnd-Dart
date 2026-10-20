import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/friend_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/friend_request_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/main_tab_prefs.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/match_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/notification_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/pending_photo_store.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/preferred_activity_prefs.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/user_gaps_store.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/user_profile_store.dart';
import 'package:gapfinderfrontend_dart/models/app_notification.dart';
import 'package:gapfinderfrontend_dart/models/friendship.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';

// What the view models call to save the network answers on the device.
// Every method returns at once (fire and forget): saving never blocks or breaks a screen,
// and if it fails it only prints.
class JoelLocalCache {
  static final JoelLocalCache instance = JoelLocalCache();

  final FriendDao friends;
  final FriendRequestDao friendRequests;
  final NotificationDao notifications;
  final MatchDao matches;
  final UserProfileStore profiles;
  final UserGapsStore gaps;
  final PendingPhotoStore pendingPhoto;
  final MainTabPrefs mainTab;
  final PreferredActivityPrefs preferredActivity;

  JoelLocalCache({
    FriendDao? friends,
    FriendRequestDao? friendRequests,
    NotificationDao? notifications,
    MatchDao? matches,
    UserProfileStore? profiles,
    UserGapsStore? gaps,
    PendingPhotoStore? pendingPhoto,
    MainTabPrefs? mainTab,
    PreferredActivityPrefs? preferredActivity,
  })  : friends = friends ?? FriendDao(),
        friendRequests = friendRequests ?? FriendRequestDao(),
        notifications = notifications ?? NotificationDao(),
        matches = matches ?? MatchDao(),
        profiles = profiles ?? UserProfileStore(),
        gaps = gaps ?? UserGapsStore(),
        pendingPhoto = pendingPhoto ?? PendingPhotoStore(),
        mainTab = mainTab ?? MainTabPrefs(),
        preferredActivity = preferredActivity ?? PreferredActivityPrefs();

  void saveFriends(int userId, List<User> list, List<Friendship> requests) {
    _run('friends', () => friends.replaceAllForUser(userId, list));
    _run('friend requests', () => friendRequests.replaceAllForUser(userId, requests));
  }

  void saveNotifications(int userId, List<AppNotification> list) {
    _run('notifications', () => notifications.replaceAllForUser(userId, list));
  }

  void saveMatches(int userId, List<Match> list, Set<int> userGapIds) {
    _run('matches', () => matches.replaceAllForUserGaps(userId, list, userGapIds));
  }

  // A match received as an invitation: the user is the acceptor
  void saveInvitationMatch(Match match) {
    _run('invitation match', () async {
      final userId = await TokenStorage.getUserId();
      if (userId == null) return;
      await matches.upsertForUser(userId, match, match.acceptorGapId);
    });
  }

  void saveGaps(int userId, List<Gap> list) {
    _run('gaps', () => gaps.save(userId, list));
  }

  // A match of the user fetched from the back (the user's own gap is found inside the match)
  void saveMatchOfUser(int userId, Match match) {
    _run('match', () => matches.upsertForUser(userId, match, _ownGapId(userId, match)));
  }

  static int? _ownGapId(int userId, Match match) {
    if (match.proposerGap?.user?.id == userId) return match.proposerGapId;
    if (match.acceptorGap?.user?.id == userId) return match.acceptorGapId;
    return null;
  }

  // Reads from the device; null if there is nothing saved or the read fails.
  // Reading never breaks a screen either: the error only prints.
  Future<T?> safeRead<T>(String what, Future<T?> Function() read) async {
    try {
      return await read();
    } catch (e) {
      debugPrint('Could not read $what from the device: $e');
      return null;
    }
  }

  // Saves the profile; load gives the full user, fallback is used if it fails
  void saveProfile(Future<User> Function() load, User fallback) {
    _run('profile', () async {
      User user;
      try {
        user = await load();
      } catch (e) {
        debugPrint('Full profile not loaded, saving the login data: $e');
        user = fallback;
      }
      await profiles.save(user);
    });
  }

  // Last preferred activity of the user (null removes it)
  void savePreferredActivity(int userId, int? activityId) {
    _run('preferred activity', () => preferredActivity.save(userId, activityId));
  }

  void saveMainTab(int tabIndex) {
    _run('main tab', () => mainTab.save(tabIndex));
  }

  void savePendingPhoto(File photo) {
    _run('pending photo', () => pendingPhoto.save(photo));
  }

  void clearPendingPhoto() {
    _run('pending photo cleanup', pendingPhoto.clear);
  }

  void _run(String what, Future<void> Function() action) {
    Future.sync(action).catchError((Object e) {
      debugPrint('Could not save $what locally: $e');
    });
  }
}
