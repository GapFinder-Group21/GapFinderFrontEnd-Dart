import 'package:gapfinderfrontend_dart/models/app_notification.dart';
import 'package:gapfinderfrontend_dart/models/friendship.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';

// Full JSON of the models for the local cache.
// The models' toJson is the request body sent to the back, so it leaves out the nested
// objects; these helpers add them back so fromJson rebuilds the same object.

Map<String, dynamic> userCacheJson(User u) => {
      ...u.toJson(),
      'createdAt': u.createdAt?.toIso8601String(),
      'interests': u.interests.map((i) => i.toJson()).toList(),
      'currentBuilding': u.currentBuilding?.toJson(),
    };

Map<String, dynamic> gapCacheJson(Gap g) => {
      ...g.toJson(),
      'user': g.user == null ? null : userCacheJson(g.user!),
    };

Map<String, dynamic> matchCacheJson(Match m) => {
      ...m.toJson(),
      'proposerGap': m.proposerGap == null ? null : gapCacheJson(m.proposerGap!),
      'acceptorGap': m.acceptorGap == null ? null : gapCacheJson(m.acceptorGap!),
    };

Map<String, dynamic> friendshipCacheJson(Friendship f) => {
      ...f.toJson(),
      'requester': f.requester == null ? null : userCacheJson(f.requester!),
      'receiver': f.receiver == null ? null : userCacheJson(f.receiver!),
    };

Map<String, dynamic> notificationCacheJson(AppNotification n) => {
      ...n.toJson(),
      'recipient': n.recipient == null ? null : userCacheJson(n.recipient!),
    };
