import 'package:gapfinderfrontend_dart/data/local/joel/cache_json.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/json_row_dao.dart';
import 'package:gapfinderfrontend_dart/models/friendship.dart';

// Friend requests received (table friend_requests, id = friendship id, with the requester inside)
class FriendRequestDao extends JsonRowDao<Friendship> {
  FriendRequestDao({super.database}) : super('friend_requests');

  @override
  int idOf(Friendship item) => item.id;

  @override
  Map<String, dynamic> toJson(Friendship item) => friendshipCacheJson(item);

  @override
  Friendship fromJson(Map<String, dynamic> json) => Friendship.fromJson(json);
}
