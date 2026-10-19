import 'package:gapfinderfrontend_dart/data/local/joel/cache_json.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/json_row_dao.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';

// Friends of the user (table friends, id = friend's user id)
class FriendDao extends JsonRowDao<User> {
  FriendDao({super.database}) : super('friends');

  @override
  int idOf(User item) => item.id;

  @override
  Map<String, dynamic> toJson(User item) => userCacheJson(item);

  @override
  User fromJson(Map<String, dynamic> json) => User.fromJson(json);
}
