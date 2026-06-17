import 'dart:ui';
import 'package:call_project/core/utils/time_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/users/data/repository/user_repository.dart';
import 'package:call_project/features/auth/repository/auth_repository.dart';
import 'package:call_project/core/providers/firebase_providers.dart';
import 'package:call_project/features/chat/presentation/screens/chat_screen.dart';
import 'package:call_project/features/chat/data/repository/chat_repository.dart';
import 'package:call_project/features/call/presentation/controllers/call_controller.dart';
import 'package:call_project/features/call/presentation/screens/call_screen.dart';
import 'package:call_project/core/navigation/navigation_service.dart';
import 'package:call_project/features/users/presentation/screens/follow_list_screen.dart';
import 'package:call_project/features/profile/presentation/screens/user_posts_screen.dart';

class AppColors {
  static const primary = Color(0xFF6366F1);
  static const secondary = Color(0xFFA855F7);
  static const background = Color(0xFFF8FAFC);
  static const success = Color(0xFF10B981);
  static const error = Color(0xFFEF4444);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
}

class UserProfileScreen extends ConsumerStatefulWidget {
  final UserModel user;
  const UserProfileScreen({super.key, required this.user});

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  Future<List<Map<String, dynamic>>>? _mediaFuture;
  List<DocumentSnapshot> _postsDocs = [];

  @override
  void initState() {
    super.initState();
    _mediaFuture = _fetchUserMedia(widget.user.uid);
  }

  Future<List<Map<String, dynamic>>> _fetchUserMedia(String uid) async {
    final postsFuture = FirebaseFirestore.instance
        .collection('posts')
        .where('uid', isEqualTo: uid)
        .get();
    final reelsFuture = FirebaseFirestore.instance
        .collection('reels')
        .where('uid', isEqualTo: uid)
        .get();

    final results = await Future.wait([postsFuture, reelsFuture]);

    final postsDocs = results[0].docs.toList();
    postsDocs.sort((a, b) {
      final aTime = parseTimestamp((a.data() as Map<String, dynamic>)['timestamp']);
      final bTime = parseTimestamp((b.data() as Map<String, dynamic>)['timestamp']);
      return bTime.compareTo(aTime);
    });
    _postsDocs = postsDocs;

    final reelsDocs = results[1].docs;

    final List<Map<String, dynamic>> allMedia = [];

    for (var doc in postsDocs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['type'] == 'image' || data['type'] == 'video') {
        data['id'] = doc.id;
        data['doc'] = doc;
        data['source'] = 'post';
        allMedia.add(data);
      }
    }

    for (var doc in reelsDocs) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;
      data['doc'] = doc;
      data['source'] = 'reel';
      data['type'] = 'video';
      allMedia.add(data);
    }

    allMedia.sort((a, b) {
      final aTime = parseTimestamp(a['timestamp']);
      final bTime = parseTimestamp(b['timestamp']);
      return bTime.compareTo(aTime);
    });
    if (mounted) {
      setState(() {});
    }

    return allMedia;
  }

  void _showOptionsMenu(
    BuildContext context,
    UserModel currentUser,
    UserModel targetUser,
    bool isFollowing,
    bool isBlocked,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            if (isFollowing)
              ListTile(
                leading: const Icon(
                  Icons.person_remove_rounded,
                  color: AppColors.error,
                ),
                title: const Text(
                  'Unfollow',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _handleFollow(
                    context,
                    ref,
                    currentUser.uid,
                    targetUser.uid,
                    false,
                    isFollowing,
                  );
                },
              ),
            ListTile(
              leading: Icon(
                isBlocked ? Icons.undo_rounded : Icons.block_rounded,
                color: AppColors.error,
              ),
              title: Text(
                isBlocked ? 'Unblock' : 'Block',
                style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _handleBlock(
                  context,
                  ref,
                  currentUser.uid,
                  targetUser.uid,
                  isBlocked,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userDetailsProvider(widget.user.uid));
    final currentUserAsync = ref.watch(currentUserDataProvider);
    final allUsersAsync = ref.watch(allUsersProvider);

    return userAsync.when(
      data: (targetUser) {
        if (targetUser == null) {
          return const Scaffold(body: Center(child: Text('User not found')));
        }

        return currentUserAsync.when(
          data: (currentUser) {
            if (currentUser == null) {
              return const Scaffold(body: Center(child: Text('Please login')));
            }

            return allUsersAsync.when(
              data: (allUsers) {
                final registeredUids = allUsers.map((u) => u.uid).toSet();

                final activeTargetFollowers = targetUser.followers
                    .where((uid) => registeredUids.contains(uid))
                    .toList();
                final activeTargetFollowing = targetUser.following
                    .where((uid) => registeredUids.contains(uid))
                    .toList();

                final isFollowing = currentUser.following.contains(
                  targetUser.uid,
                );
                final hasRequested = targetUser.pendingFollowRequests.contains(
                  currentUser.uid,
                );
                final isBlocked = currentUser.blockedUsers.contains(
                  targetUser.uid,
                );
                final canInteract =
                    isFollowing &&
                    targetUser.following.contains(currentUser.uid);

                return Scaffold(
                  backgroundColor: AppColors.background,
                  body: DefaultTabController(
                    length: 2,
                    child: NestedScrollView(
                      headerSliverBuilder: (context, innerBoxIsScrolled) {
                        return [
                          SliverAppBar(
                            backgroundColor: AppColors.background,
                            elevation: innerBoxIsScrolled ? 1 : 0,
                            pinned: true,
                            leading: IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: AppColors.textPrimary,
                                size: 20,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            title: Text(
                              targetUser.displayName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            actions: [
                              IconButton(
                                icon: const Icon(
                                  Icons.more_vert_rounded,
                                  color: AppColors.textPrimary,
                                ),
                                onPressed: () => _showOptionsMenu(
                                  context,
                                  currentUser,
                                  targetUser,
                                  isFollowing,
                                  isBlocked,
                                ),
                              ),
                            ],
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Column(
                                children: [
                                  _buildProfileHeaderCard(
                                    context,
                                    ref,
                                    targetUser,
                                    currentUser,
                                    hasRequested,
                                    isFollowing,
                                    activeTargetFollowers,
                                    activeTargetFollowing,
                                  ),
                                  const SizedBox(height: 16),
                                  if (!isBlocked) ...[
                                    if (canInteract)
                                      _buildActionsBento(
                                        context,
                                        ref,
                                        currentUser,
                                        targetUser,
                                      )
                                    else
                                      _buildLockedBento(),
                                    const SizedBox(height: 16),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (isFollowing)
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _SliverAppBarDelegate(
                                const TabBar(
                                  indicatorColor: AppColors.primary,
                                  labelColor: AppColors.primary,
                                  unselectedLabelColor: AppColors.textSecondary,
                                  tabs: [
                                    Tab(icon: Icon(Icons.grid_on_rounded)),
                                    Tab(
                                      icon: Icon(Icons.ondemand_video_rounded),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ];
                      },
                      body: isFollowing
                          ? FutureBuilder<List<Map<String, dynamic>>>(
                              future: _mediaFuture,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                if (snapshot.hasError) {
                                  return Center(
                                    child: Text(
                                      'Error: ${snapshot.error}',
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  );
                                }
                                final allMedia = snapshot.data ?? [];
                                final videosOnly = allMedia
                                    .where((m) => m['type'] == 'video')
                                    .toList();

                                return TabBarView(
                                  children: [
                                    _buildMediaGrid(
                                      allMedia,
                                      currentUser,
                                      targetUser,
                                      isVideosOnly: false,
                                    ),
                                    _buildMediaGrid(
                                      videosOnly,
                                      currentUser,
                                      targetUser,
                                      isVideosOnly: true,
                                    ),
                                  ],
                                );
                              },
                            )
                          : _buildPrivateAccountView(),
                    ),
                  ),
                );
              },
              loading: () => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
              error: (e, st) =>
                  Scaffold(body: Center(child: Text('Error: $e'))),
            );
          },
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  Widget _buildMediaGrid(
    List<Map<String, dynamic>> mediaList,
    UserModel currentUser,
    UserModel targetUser, {
    bool isVideosOnly = false,
  }) {
    if (mediaList.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined, size: 48, color: Colors.black26),
            SizedBox(height: 16),
            Text(
              'No Posts Yet',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: mediaList.length,
      itemBuilder: (context, index) {
        final media = mediaList[index];
        final isReel = media['source'] == 'reel';
        final isVideo = media['type'] == 'video';
        final thumbnailUrl = media['thumbnailUrl'] ?? media['thumbnail'] ?? media['mediaUrl'];

        return GestureDetector(
          onTap: () {
            if (media['source'] == 'reel') {
              final docsToPass = mediaList.map((m) => m['doc'] as DocumentSnapshot).toList();
              int targetIndex = docsToPass.indexWhere((doc) => doc.id == media['id']);
              if (targetIndex == -1) targetIndex = 0;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserPostsScreen(
                    currentUser: currentUser,
                    targetUserId: targetUser.uid,
                    initialIndex: targetIndex,
                    posts: docsToPass,
                  ),
                ),
              );
              return;
            }

            final postsToPass = isVideosOnly
                ? _postsDocs
                      .where(
                        (p) =>
                            (p.data() as Map<String, dynamic>)['type'] ==
                            'video',
                      )
                      .toList()
                : _postsDocs;

            int targetIndex = postsToPass.indexWhere(
              (p) => p.id == media['id'],
            );
            if (targetIndex != -1) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserPostsScreen(
                    currentUser: currentUser,
                    targetUserId: targetUser.uid,
                    initialIndex: targetIndex,
                    posts: postsToPass,
                  ),
                ),
              );
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.grey.shade200),
              if (thumbnailUrl != null && thumbnailUrl.toString().isNotEmpty)
                CachedNetworkImage(
                  imageUrl: thumbnailUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (context, url, error) =>
                      const Icon(Icons.error, color: Colors.grey),
                ),
              if (isVideo)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              if (isReel)
                const Positioned(
                  bottom: 8,
                  left: 8,
                  child: Icon(
                    Icons.movie_creation_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileHeaderCard(
    BuildContext context,
    WidgetRef ref,
    UserModel targetUser,
    UserModel currentUser,
    bool hasRequested,
    bool isFollowing,
    List<String> activeFollowers,
    List<String> activeFollowing,
  ) {
    final now = DateTime.now();
    final isActuallyOnline = targetUser.isOnline && targetUser.lastSeen != null && now.difference(targetUser.lastSeen!).inMinutes < 2;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Hero(
                tag: 'profile_${targetUser.uid}',
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    image: targetUser.photoUrl != null
                        ? DecorationImage(
                            image: CachedNetworkImageProvider(targetUser.photoUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: targetUser.photoUrl == null
                      ? Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              targetUser.displayName[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 26,
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn('Posts', '${_postsDocs.length}'),
                    _buildStatColumn(
                      'Followers', 
                      '${activeFollowers.length}',
                      onTap: isFollowing ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => FollowListScreen(title: 'Followers', uids: activeFollowers))) : null,
                    ),
                    _buildStatColumn(
                      'Following', 
                      '${activeFollowing.length}',
                      onTap: isFollowing ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => FollowListScreen(title: 'Following', uids: activeFollowing))) : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            targetUser.displayName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isActuallyOnline ? AppColors.success : AppColors.textSecondary.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isActuallyOnline ? 'Active now' : _formatLastSeen(targetUser.lastSeen, now),
                style: TextStyle(
                  color: isActuallyOnline ? AppColors.success : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: ElevatedButton(
              onPressed: () => _handleFollow(context, ref, currentUser.uid, targetUser.uid, hasRequested, isFollowing),
              style: ElevatedButton.styleFrom(
                backgroundColor: isFollowing ? Colors.white : AppColors.primary,
                foregroundColor: isFollowing ? AppColors.primary : Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: isFollowing ? BorderSide(color: Colors.black.withValues(alpha: 0.1), width: 1) : BorderSide.none,
                ),
              ),
              child: Text(
                isFollowing ? 'Following' : (hasRequested ? 'Request Sent' : 'Follow'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String count, {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(count, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionsBento(
    BuildContext context,
    WidgetRef ref,
    UserModel currentUser,
    UserModel targetUser,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 16),
            child: Text(
              'QUICK ACTIONS',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildInteractionCircle(
                ref,
                'Message',
                Icons.chat_bubble_rounded,
                AppColors.primary,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(receiver: targetUser),
                    ),
                  );
                },
                targetUser.uid,
                currentUser.uid,
              ),
              _buildInteractionCircle(
                ref,
                'Audio Call',
                Icons.phone_rounded,
                AppColors.success,
                () {
                  _makeCall(context, ref, currentUser, targetUser, true);
                },
                null,
                null,
              ),
              _buildInteractionCircle(
                ref,
                'Video Call',
                Icons.videocam_rounded,
                AppColors.secondary,
                () {
                  _makeCall(context, ref, currentUser, targetUser, false);
                },
                null,
                null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLockedBento() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Private Account',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Follow this account to see their photos and videos.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionCircle(
    WidgetRef ref,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
    String? targetId,
    String? currentId,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: color, size: 24),
                  if (targetId != null && currentId != null)
                    _buildUnreadBadge(ref, currentId, targetId),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnreadBadge(WidgetRef ref, String currentId, String targetId) {
    final unreadCountAsync = ref.watch(
      unreadChatMessagesCountProvider(
        currentUserId: currentId,
        otherUserId: targetId,
      ),
    );
    return unreadCountAsync.when(
      data: (count) => count > 0
          ? Positioned(
              right: -8,
              top: -8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : const SizedBox.shrink(),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _handleFollow(
    BuildContext context,
    WidgetRef ref,
    String currentUid,
    String targetUid,
    bool hasRequested,
    bool isFollowing,
  ) {
    if (isFollowing) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Unfollow User?'),
          content: const Text(
            'You will no longer be able to message or call this user private until you follow each other again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                ref
                    .read(userRepositoryProvider)
                    .unfollowUser(currentUid, targetUid);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Unfollow'),
            ),
          ],
        ),
      );
      return;
    }

    if (hasRequested) {
      ref
          .read(userRepositoryProvider)
          .cancelFollowRequest(currentUid, targetUid);
    } else {
      ref.read(userRepositoryProvider).sendFollowRequest(currentUid, targetUid);
    }
  }

  void _handleBlock(
    BuildContext context,
    WidgetRef ref,
    String currentUid,
    String targetUid,
    bool isBlocked,
  ) {
    if (isBlocked) {
      ref.read(userRepositoryProvider).unblockUser(currentUid, targetUid);
    } else {
      ref.read(userRepositoryProvider).blockUser(currentUid, targetUid);
    }
  }

  void _makeCall(
    BuildContext context,
    WidgetRef ref,
    UserModel currentUser,
    UserModel targetUser,
    bool isAudioCall,
  ) async {
    final newChannelId = await ref
        .read(callControllerProvider.notifier)
        .makeCall(
          senderId: currentUser.uid,
          senderName: currentUser.displayName,
          receiverId: targetUser.uid,
          receiverName: targetUser.displayName,
          receiverToken: targetUser.fcmToken ?? '',
          isAudioCall: isAudioCall,
          context: context,
        );

    if (newChannelId != null && context.mounted) {
      globalActiveCallId = newChannelId;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(
            channelId: newChannelId,
            guestUser: targetUser,
            isAudioCall: isAudioCall,
            isOutgoing: true,
          ),
        ),
      );
    }
  }

  String _formatLastSeen(DateTime? lastSeen, DateTime now) {
    if (lastSeen == null) return 'Never';
    final difference = now.difference(lastSeen);
    if (difference.inMinutes < 60) return 'Active ${difference.inMinutes}m ago';
    if (difference.inHours < 24) return 'Active ${difference.inHours}h ago';
    return 'Active ${difference.inDays}d ago';
  }
}

Widget _buildPrivateAccountView() {
  return const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 64, color: Colors.black26),
        SizedBox(height: 16),
        Text(
          'This account is private',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Follow this account to see their photos and videos.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  _SliverAppBarDelegate(this._tabBar);
  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: Colors.white, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
