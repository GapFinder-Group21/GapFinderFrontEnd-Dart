import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/token_storage.dart';
import '../../models/user.dart';
import '../../models/gap.dart';
import '../../services/friendship_service.dart';
import '../../services/gap_service.dart';
import '../../services/user_service.dart';
import '../../widgets/common/avatar_widget.dart';

/// Friends tab: search users, send and answer friend requests,
/// and see which friends are free right now and which are in class.
class FriendsScreen extends StatefulWidget {
  final bool isActive;
  const FriendsScreen({super.key, this.isActive = false});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

// A friend together with their current free gap (if any)
class _FriendWithGap {
  final User user;
  final Gap? gap;
  _FriendWithGap(this.user, this.gap);
}

// A friend request received, with the user who sent it
class _PendingRequest {
  final int friendshipId;
  final User user;
  _PendingRequest(this.friendshipId, this.user);
}

// Everything the screen shows: free friends, friends in class and pending requests
class _FriendsData {
  final List<_FriendWithGap> freeNow;
  final List<User> inClass;
  final List<_PendingRequest> pendingRequests;
  _FriendsData({required this.freeNow, required this.inClass, required this.pendingRequests});
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _friendshipService = FriendshipService();
  final _gapService = GapService();
  final _userService = UserService();
  
  late Future<_FriendsData> _friendsFuture;
  final _searchController = TextEditingController();
  List<User> _searchResults = [];
  bool _isSearching = false;

  @override
  // Load the friends when the screen opens
  void initState() {
    super.initState();
    _friendsFuture = _loadFriends();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FriendsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload the data every time the user comes back to this tab
    if (widget.isActive && !oldWidget.isActive) {
      _refresh();
    }
  }

  // Searches users by name - GET /users/search?name=
  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await _userService.searchByName(query.trim());
      final currentUserId = await TokenStorage.getUserId();
      setState(() {
        _searchResults = results.where((u) => u.id != currentUserId).toList();
      });
    } catch (e) {
      debugPrint('Error searching users: $e');
    }
  }

  // Sends a friend request - POST /friendships
  Future<void> _sendFriendRequest(int targetUserId) async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return;
    try {
      await _friendshipService.sendRequest(userId, targetUserId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request sent!')),
        );
        _searchController.clear();
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    }
  }

  // Accepts a friend request - PATCH /friendships/{id}/accept
  Future<void> _acceptRequest(int friendshipId) async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return;
    try {
      await _friendshipService.acceptRequest(friendshipId, userId);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accepting request: $e')),
        );
      }
    }
  }

  // Rejects a friend request - PATCH /friendships/{id}/reject
  Future<void> _rejectRequest(int friendshipId) async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return;
    try {
      await _friendshipService.rejectRequest(friendshipId, userId);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error rejecting request: $e')),
        );
      }
    }
  }

  // Loads the friends (split into "with GAP now" and "in class") and the pending requests
  Future<_FriendsData> _loadFriends() async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return _FriendsData(freeNow: [], inClass: [], pendingRequests: []);

    final friends = await _friendshipService.getFriendsByUser(userId);
    final pending = await _friendshipService.getPendingReceived(userId);
    
    final pendingRequests = <_PendingRequest>[];
    for (final p in pending) {
      User? u = p.requester;
      if (u == null && p.requesterId != null) {
        try {
          u = await _userService.getUser(p.requesterId!);
        } catch (_) {}
      }
      if (u != null) {
        pendingRequests.add(_PendingRequest(p.id, u));
      }
    }

    final now = DateTime.now();
    final freeNow = <_FriendWithGap>[];
    final inClass = <User>[];

    final friendsGaps = await Future.wait(friends.map(_loadFriendGaps));

    for (var i = 0; i < friends.length; i++) {
      final u = friends[i];
      final current = friendsGaps[i]
          .where((g) => !now.isBefore(g.startTime) && now.isBefore(g.endTime))
          .firstOrNull;

      if (current != null) {
        freeNow.add(_FriendWithGap(u, current));
      } else {
        inClass.add(u);
      }
    }

    return _FriendsData(freeNow: freeNow, inClass: inClass, pendingRequests: pendingRequests);
  }

  // Gets a friend's gaps for this week - GET /gaps/user/{userId}
  // If the friend has no gaps yet, they are generated from the friend's classes
  // POST /gaps/user/{userId}/generate-week
  Future<List<Gap>> _loadFriendGaps(User friend) async {
    try {
      final gaps = await _gapService.getUserGaps(friend.id);
      if (gaps.isNotEmpty) return gaps;
      return await _gapService.generateWeek(friend.id);
    } catch (e) {
      debugPrint('No se pudieron cargar los gaps de ${friend.name}: $e');
      return [];
    }
  }

  // Reload everything (pull to refresh)
  Future<void> _refresh() async {
    setState(() {
      _friendsFuture = _loadFriends();
    });
  }

  // Formats a time for the cards
  String _formatTime(DateTime time) {
    final t = TimeOfDay.fromDateTime(time);
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String? _gapWindowLabel(Gap? gap) {
    if (gap == null) return null;
    return '${_formatTime(gap.startTime)} – ${_formatTime(gap.endTime)}';
  }

  // Gets the text of an interest, whatever type it comes as
  String _interestLabel(dynamic interest) {
    if (interest is String) return interest;
    try {
      return interest.name ?? '';
    } catch (_) {
      return interest.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            Expanded(
              child: FutureBuilder<_FriendsData>(
                future: _friendsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return _buildErrorState();
                  }

                  final data = snapshot.data!;

                  if (_isSearching) {
                    return _buildSearchResults();
                  }

                  final hasNoFriends = data.freeNow.isEmpty && data.inClass.isEmpty && data.pendingRequests.isEmpty;

                  if (hasNoFriends) {
                    return _buildEmptyState();
                  }

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (data.pendingRequests.isNotEmpty) ...[
                          _buildSectionHeader(
                            label: 'Friend Requests',
                            count: data.pendingRequests.length,
                            dotColor: AppColors.accent3,
                          ),
                          const SizedBox(height: 14),
                          ...data.pendingRequests.map(_buildPendingRequestCard),
                          const SizedBox(height: 20),
                        ],
                        if (data.freeNow.isNotEmpty) ...[
                          _buildSectionHeader(
                            label: 'With GAP now',
                            count: data.freeNow.length,
                            dotColor: AppColors.accent1,
                          ),
                          const SizedBox(height: 14),
                          ...data.freeNow.map(_buildFreeNowCard),
                        ],
                        if (data.inClass.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _buildSectionHeader(
                            label: 'In class',
                            count: data.inClass.length,
                            dotColor: AppColors.contrast.withValues(alpha: 0.18),
                            textColor: AppColors.contrast.withValues(alpha: 0.3),
                            small: true,
                          ),
                          const SizedBox(height: 12),
                          _buildInClassGrid(data.inClass),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Search bar to find users by name
  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: TextField(
        controller: _searchController,
        onChanged: _searchUsers,
        style: AppFonts.body().copyWith(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search users by name...',
          hintStyle: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.4)),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.contrast),
          suffixIcon: _isSearching || _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () {
                    _searchController.clear();
                    _searchUsers('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.background,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.contrast.withValues(alpha: 0.1), width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.contrast.withValues(alpha: 0.1), width: 1.5),
          ),
        ),
      ),
    );
  }

  // Results of the search, each one with an "Add" button
  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          'No users found',
          style: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.5)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.contrast.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              _buildAvatar(user.avatarUrl, name: user.name, size: 44, borderColor: AppColors.contrast.withValues(alpha: 0.1), borderWidth: 1.5),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: AppFonts.display(weight: FontWeight.w800).copyWith(fontSize: 15, color: AppColors.contrast),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${user.career} · Sem ${user.semester ?? 1}',
                      style: AppFonts.body().copyWith(fontSize: 12, color: AppColors.contrast.withValues(alpha: 0.45)),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => _sendFriendRequest(user.id),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent2,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  minimumSize: const Size(70, 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text('Add', style: AppFonts.display(weight: FontWeight.w900).copyWith(fontSize: 11)),
              ),
            ],
          ),
        );
      },
    );
  }

  // Card of a received friend request with Accept and Reject buttons
  Widget _buildPendingRequestCard(_PendingRequest req) {
    final user = req.user;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent3.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.contrast.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildAvatar(user.avatarUrl, name: user.name, size: 48, borderColor: AppColors.accent3, borderWidth: 2),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: 15,
                    color: AppColors.contrast,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${user.career} · Sem ${user.semester ?? 1}',
                  style: AppFonts.body().copyWith(
                    fontSize: 12,
                    color: AppColors.contrast.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => _acceptRequest(req.friendshipId),
                icon: const Icon(Icons.check_circle_rounded, color: AppColors.accent2, size: 32),
                tooltip: 'Accept',
              ),
              IconButton(
                onPressed: () => _rejectRequest(req.friendshipId),
                icon: const Icon(Icons.cancel_rounded, color: AppColors.accent1, size: 32),
                tooltip: 'Reject',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Dark header with the title and the friends avatars
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: AppColors.contrast,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: FutureBuilder<_FriendsData>(
        future: _friendsFuture,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final all = [
            ...?data?.freeNow.map((f) => f.user),
            ...?data?.inClass,
          ];

          return Row(
            children: [
              Text(
                'Friends',
                style: AppFonts.display(weight: FontWeight.w800).copyWith(
                  fontSize: 20,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 10),
              if (all.isNotEmpty)
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: AppColors.accent2,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${all.length}',
                    style: AppFonts.display(weight: FontWeight.w800).copyWith(
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              const Spacer(),
              if (all.isNotEmpty) _buildAvatarStack(all.take(5).toList()),
            ],
          );
        },
      ),
    );
  }

  // Small overlapped avatars of the first friends
  Widget _buildAvatarStack(List<User> users) {
    return SizedBox(
      height: 32,
      width: 32.0 + (users.length - 1) * 22.0,
      child: Stack(
        children: [
          for (int i = 0; i < users.length; i++)
            Positioned(
              left: i * 22.0,
              child: _buildAvatar(
                users[i].avatarUrl,
                name: users[i].name,
                size: 32,
                borderColor: AppColors.contrast,
                borderWidth: 2,
              ),
            ),
        ],
      ),
    );
  }

  // Title of a section ("Friend Requests", "With GAP now", "In class")
  Widget _buildSectionHeader({
    required String label,
    required int count,
    required Color dotColor,
    Color? textColor,
    bool small = false,
  }) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: AppFonts.display(weight: FontWeight.w800).copyWith(
            fontSize: small ? 14 : 16,
            color: textColor ?? AppColors.contrast,
          ),
        ),
        const SizedBox(width: 8),
        if (!small)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: const BoxDecoration(color: AppColors.accent1, borderRadius: BorderRadius.all(Radius.circular(12))),
            alignment: Alignment.center,
            child: Text(
              '$count',
              style: AppFonts.display(weight: FontWeight.w800).copyWith(
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          )
        else
          Text(
            '$count',
            style: AppFonts.display(weight: FontWeight.w800).copyWith(
              fontSize: 14,
              color: AppColors.contrast.withValues(alpha: 0.2),
            ),
          ),
      ],
    );
  }

  // Card of a friend who has a GAP right now, with their free time
  Widget _buildFreeNowCard(_FriendWithGap f) {
    final user = f.user;
    final windowLabel = _gapWindowLabel(f.gap);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent2.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.contrast.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Stack(
                  children: [
                    _buildAvatar(user.avatarUrl, name: user.name, size: 48, borderColor: AppColors.accent2, borderWidth: 2),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.accent2,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: AppFonts.display(weight: FontWeight.w800).copyWith(
                          fontSize: 15,
                          color: AppColors.contrast,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${user.career} · ${user.semester}',
                        style: AppFonts.body().copyWith(
                          fontSize: 12,
                          color: AppColors.contrast.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (windowLabel != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accent2.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time, size: 13, color: AppColors.accent2),
                  const SizedBox(width: 6),
                  Text(
                    windowLabel,
                    style: AppFonts.display(weight: FontWeight.w700).copyWith(
                      fontSize: 12,
                      color: AppColors.accent2,
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: user.interests.take(3).map((interest) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.contrast.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _interestLabel(interest),
                    style: AppFonts.body(weight: FontWeight.w700).copyWith(
                      fontSize: 10,
                      color: AppColors.contrast.withValues(alpha: 0.5),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // Grid of friends who are in class (Wrap so it never overflows)
  Widget _buildInClassGrid(List<User> users) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: users.map((user) {
        final screenWidth = MediaQuery.of(context).size.width;
        final itemWidth = (screenWidth - 32 - 24) / 3; // 3 columns minus padding and spacing

        return Opacity(
          opacity: 0.7,
          child: Container(
            width: itemWidth,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.contrast.withValues(alpha: 0.08), width: 1),
            ),
            child: Column(
              children: [
                _buildAvatar(user.avatarUrl, name: user.name, size: 36, borderColor: AppColors.contrast.withValues(alpha: 0.1), borderWidth: 1.5),
                const SizedBox(height: 8),
                Text(
                  user.name.split(' ').first,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.body(weight: FontWeight.w700).copyWith(
                    fontSize: 11,
                    color: AppColors.contrast,
                  ),
                ),
                Text(
                  'In class',
                  style: AppFonts.body().copyWith(
                    fontSize: 10,
                    color: AppColors.contrast.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // Round avatar: photo or the first letter of the name
  Widget _buildAvatar(String? url, {String? name, required double size, required Color borderColor, required double borderWidth}) {
    return AvatarWidget(
      url: url,
      name: name,
      size: size,
      border: Border.all(color: borderColor, width: borderWidth),
    );
  }

  // Shown when the user has no friends yet
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: AppColors.contrast.withValues(alpha: 0.15)),
            const SizedBox(height: 20),
            Text(
              'No friends added yet',
              style: AppFonts.display(weight: FontWeight.w800).copyWith(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Add friends to see when they have free GAPs.',
              textAlign: TextAlign.center,
              style: AppFonts.body().copyWith(color: AppColors.contrast.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }

  // Shown when the friends could not be loaded
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 48, color: AppColors.contrast.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('Something went wrong', style: AppFonts.body(weight: FontWeight.w700)),
          TextButton(onPressed: _refresh, child: const Text('Try again')),
        ],
      ),
    );
  }
}
