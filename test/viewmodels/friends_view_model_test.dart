import 'noop_local_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/models/enums/friendship_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/friendship.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/friendship_service.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/services/user_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/friends/friends_view_model.dart';

import 'secure_storage_mock.dart';

User _user(int id, String name) =>
    User(id: id, name: name, email: '$name@test.com', career: 'Systems');

Friendship _friendship(int id, User requester) => Friendship(
      id: id,
      status: FriendshipStatusEnum.pending,
      createdAt: DateTime(2026, 1, 1),
      requesterId: requester.id,
      requester: requester,
    );

class FakeFriendshipService extends FriendshipService {
  List<User> friends = [];
  List<Friendship> pending = [];
  Object? error;
  final calls = <String>[];

  @override
  Future<List<User>> getFriendsByUser(int userId) async => friends;

  @override
  Future<List<Friendship>> getPendingReceived(int userId) async => pending;

  @override
  Future<Friendship> sendRequest(int requesterId, int receiverId) async {
    calls.add('send:$receiverId');
    if (error != null) throw error!;
    return _friendship(99, _user(requesterId, 'me'));
  }

  @override
  Future<Friendship> acceptRequest(int id, int userId) async {
    calls.add('accept:$id');
    if (error != null) throw error!;
    pending = [];
    return _friendship(id, _user(2, 'ana'));
  }

  @override
  Future<Friendship> rejectRequest(int id, int userId) async {
    calls.add('reject:$id');
    if (error != null) throw error!;
    pending = [];
    return _friendship(id, _user(2, 'ana'));
  }
}

class FakeGapService extends GapService {
  Map<int, List<Gap>> gapsByUser = {};

  @override
  Future<List<Gap>> getUserGaps(int userId, {String? weekStart}) async =>
      gapsByUser[userId] ?? [];
}

class FakeUserService extends UserService {
  int searchCalls = 0;

  @override
  Future<List<User>> searchByName(String name) async {
    searchCalls++;
    return [_user(1, 'me'), _user(2, 'ana')];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = SecureStorageMock();
  late FakeFriendshipService friendships;
  late FakeGapService gaps;
  late FakeUserService users;
  late FriendsViewModel vm;

  setUp(() {
    storage.install();
    storage.setUserId(1);
    friendships = FakeFriendshipService();
    gaps = FakeGapService();
    users = FakeUserService();
    FriendsViewModel.clearSearchCache();
    vm = FriendsViewModel(
      friendshipService: friendships,
      gapService: gaps,
      userService: users,
      localCache: NoopLocalCache(),
    );
  });

  tearDown(() {
    vm.dispose();
    storage.uninstall();
  });

  group('FriendsViewModel', () {
    test('initial state: loading and no data', () {
      expect(vm.isLoading, isTrue);
      expect(vm.data, isNull);
      expect(vm.hasError, isFalse);
      expect(vm.allFriends, isEmpty);
    });

    test('init() splits friends into free now and in class, plus requests',
        () async {
      final ana = _user(2, 'ana');
      final luis = _user(3, 'luis');
      final now = DateTime.now();
      friendships.friends = [ana, luis];
      friendships.pending = [_friendship(10, _user(4, 'sara'))];
      gaps.gapsByUser[2] = [
        Gap(
          id: 1,
          startTime: now.subtract(const Duration(minutes: 10)),
          endTime: now.add(const Duration(minutes: 50)),
        ),
      ];

      await vm.init();

      expect(vm.isLoading, isFalse);
      expect(vm.hasError, isFalse);
      expect(vm.data!.freeNow.map((f) => f.user.id), [2]);
      expect(vm.data!.inClass.map((u) => u.id), [3]);
      expect(vm.data!.pendingRequests.single.friendshipId, 10);
      expect(vm.allFriends, hasLength(2));
      expect(vm.hasNoFriends, isFalse);
    });

    test('hasNoFriends is true when there are no friends and no requests',
        () async {
      await vm.init();

      expect(vm.hasNoFriends, isTrue);
    });

    test('send, accept and reject return true and refresh the state',
        () async {
      friendships.pending = [_friendship(10, _user(4, 'sara'))];
      await vm.init();
      expect(vm.data!.pendingRequests, hasLength(1));

      expect(await vm.sendFriendRequest(5), isTrue);
      expect(await vm.acceptRequest(10), isTrue);
      await settle();
      expect(vm.data!.pendingRequests, isEmpty);

      expect(await vm.rejectRequest(11), isTrue);
      expect(friendships.calls, ['send:5', 'accept:10', 'reject:11']);
    });

    test('send, accept and reject return false and set errorMessage on error',
        () async {
      friendships.error = Exception('already friends');

      expect(await vm.sendFriendRequest(5), isFalse);
      expect(vm.errorMessage, 'already friends');

      expect(await vm.acceptRequest(10), isFalse);
      expect(vm.errorMessage, contains('Error accepting request'));

      expect(await vm.rejectRequest(10), isFalse);
      expect(vm.errorMessage, contains('Error rejecting request'));
    });

    test('actions return null when there is no session', () async {
      storage.values.clear();

      expect(await vm.sendFriendRequest(5), isNull);
      expect(await vm.acceptRequest(10), isNull);
      expect(await vm.rejectRequest(10), isNull);
      expect(friendships.calls, isEmpty);
    });

    test('searching the same text again uses the LRU cache, ignoring capitals and extra spaces', () async {
      await vm.search('Ana');
      await vm.search('  ana ');
      await vm.search('ANA');

      expect(users.searchCalls, 1);
      // The user themself is filtered out of the cached results too
      expect(vm.searchResults.map((u) => u.id), [2]);

      await vm.search('leo');
      expect(users.searchCalls, 2);
    });
  });
}
