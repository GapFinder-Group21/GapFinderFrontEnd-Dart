// Types and dedupe keys of the actions queued in the outbox.
// A dedupe key means "only one pending action with this key": tapping nine times without
// connection leaves one row, so when the network comes back the action is sent once.
class OutboxTypes {
  static const friendRequestSend = 'friend_request_send';
  static const friendRequestAccept = 'friend_request_accept';
  static const friendRequestReject = 'friend_request_reject';
  static const matchInvitationAccept = 'match_invitation_accept';
  static const matchInvitationDecline = 'match_invitation_decline';
  static const photoUpload = 'photo_upload';
}

class OutboxKeys {
  // One request per target user
  static String friendRequestSend(int targetUserId) => 'friend_request_send:$targetUserId';

  // Accept and reject share the key: only one decision can be pending per request
  static String friendRequestDecision(int friendshipId) => 'friend_request_$friendshipId';

  // Accept and decline share the key, same idea
  static String matchInvitation(int matchId) => 'match_invitation_$matchId';

  static String photoUpload(String photoPath) => 'photo_upload:$photoPath';

  // Keys that belong to the friends screen
  static bool isFriendKey(String key) => key.startsWith('friend_request_');
}
