import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

// Unified Design System Colors
class AppColors {
  static const primary = Color(0xFF6366F1); // Indigo
  static const secondary = Color(0xFFA855F7); // Purple
  static const background = Color(0xFFF8FAFC); // Slate Light
  static const darkSurface = Color(0xFF0F172A); // Midnight
  static const success = Color(0xFF10B981); // Emerald
  static const error = Color(0xFFEF4444); // Rose
  static const textPrimary = Color(0xFF1E293B);
  static const textSecondary = Color(0xFF64748B);
}

class UserProfileScreen extends ConsumerWidget {
  final UserModel user;
  const UserProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userDetailsProvider(user.uid));
    final currentUserAsync = ref.watch(currentUserDataProvider);

    return userAsync.when(
      data: (targetUser) {
        if (targetUser == null)
          return const Scaffold(body: Center(child: Text('User not found')));

        return currentUserAsync.when(
          data: (currentUser) {
            if (currentUser == null)
              return const Scaffold(body: Center(child: Text('Please login')));

            final isFollowing = currentUser.following.contains(targetUser.uid);
            final hasRequested = targetUser.pendingFollowRequests.contains(
              currentUser.uid,
            );
            final isBlocked = currentUser.blockedUsers.contains(targetUser.uid);
            final canInteract =
                isFollowing && targetUser.following.contains(currentUser.uid);

            return Scaffold(
              backgroundColor: AppColors.background,
              body: Stack(
                children: [
                  // Fixed Curved Header
                  _buildCurvedHeader(context),

                  // Scrollable Content
                  SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(
                          height: 100,
                        ), // Spacing for avatar positioning
                        _buildProfileCard(context, targetUser),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              _buildStatsRow(context, targetUser, isFollowing),
                              const SizedBox(height: 20),
                              if (!isBlocked)
                                _buildMainActions(
                                  context,
                                  ref,
                                  currentUser,
                                  targetUser,
                                  hasRequested,
                                  isFollowing,
                                  canInteract,
                                ),
                              const SizedBox(height: 20),
                              _buildDangerZone(
                                context,
                                ref,
                                currentUser.uid,
                                targetUser.uid,
                                isBlocked,
                              ),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Fixed Back Button
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 10,
                    left: 16,
                    child: CircleAvatar(
                      backgroundColor: Colors.black.withValues(alpha: 0.2),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ],
              ),
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

  Widget _buildCurvedHeader(BuildContext context) {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.secondary],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(50),
          bottomRight: Radius.circular(50),
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, UserModel user) {
    final now = DateTime.now();
    final isActuallyOnline =
        user.isOnline &&
        user.lastSeen != null &&
        now.difference(user.lastSeen!).inMinutes < 2;

    return Column(
      children: [
        Hero(
          tag: 'profile_${user.uid}',
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
              image: user.photoUrl != null
                  ? DecorationImage(
                      image: NetworkImage(user.photoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: user.photoUrl == null
                ? Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        user.displayName[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 48,
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          user.displayName,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isActuallyOnline
                    ? AppColors.success
                    : AppColors.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isActuallyOnline ? 'Active now' : _formatLastSeen(user.lastSeen, now),
              style: TextStyle(
                color: isActuallyOnline
                    ? AppColors.success
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsRow(
    BuildContext context,
    UserModel user,
    bool isFollowing,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(
            context,
            'Followers',
            user.followers.length,
            user.followers,
            isFollowing,
          ),
          Container(
            width: 1,
            height: 30,
            color: Colors.grey.withValues(alpha: 0.1),
          ),
          _buildStatItem(
            context,
            'Following',
            user.following.length,
            user.following,
            isFollowing,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    int count,
    List<String> uids,
    bool isFollowing,
  ) {
    return GestureDetector(
      onTap: isFollowing
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FollowListScreen(title: label, uids: uids),
                ),
              );
            }
          : null,
      child: Column(
        children: [
          Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainActions(
    BuildContext context,
    WidgetRef ref,
    UserModel currentUser,
    UserModel targetUser,
    bool hasRequested,
    bool isFollowing,
    bool canInteract,
  ) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: () => _handleFollow(
              context,
              ref,
              currentUser.uid,
              targetUser.uid,
              hasRequested,
              isFollowing,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isFollowing ? Colors.white : AppColors.primary,
              foregroundColor: isFollowing ? AppColors.primary : Colors.white,
              elevation: isFollowing ? 0 : 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: isFollowing
                    ? BorderSide(color: AppColors.primary.withValues(alpha: 0.2), width: 1)
                    : BorderSide.none,
              ),
              shadowColor: AppColors.primary.withValues(alpha: 0.3),
            ),
            child: Text(
              isFollowing
                  ? 'Following'
                  : (hasRequested ? 'Request Sent' : 'Follow'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (canInteract)
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1,
            children: [
              _buildInteractionItem(
                ref,
                'Chat',
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
              _buildInteractionItem(
                ref,
                'Call',
                Icons.phone_rounded,
                AppColors.success,
                () {
                  _makeCall(context, ref, currentUser, targetUser, true);
                },
                null,
                null,
              ),
              _buildInteractionItem(
                ref,
                'Video',
                Icons.videocam_rounded,
                AppColors.secondary,
                () {
                  _makeCall(context, ref, currentUser, targetUser, false);
                },
                null,
                null,
              ),
            ],
          )
        else
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_rounded, color: AppColors.primary, size: 24),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Follow each other to unlock private chat and calling features.',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildInteractionItem(
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
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 28),
                if (targetId != null && currentId != null)
                  _buildUnreadBadge(ref, currentId, targetId),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
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

  Widget _buildDangerZone(
    BuildContext context,
    WidgetRef ref,
    String currentUid,
    String targetUid,
    bool isBlocked,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'PRIVACY SETTINGS',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.05)),
          ),
          child: ListTile(
            onTap: () =>
                _handleBlock(context, ref, currentUid, targetUid, isBlocked),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: (isBlocked ? AppColors.primary : AppColors.error)
                  .withValues(alpha: 0.1),
              child: Icon(
                isBlocked ? Icons.undo_rounded : Icons.block_rounded,
                color: isBlocked ? AppColors.primary : AppColors.error,
                size: 20,
              ),
            ),
            title: Text(
              isBlocked ? 'Unblock User' : 'Block User',
              style: TextStyle(
                color: isBlocked ? AppColors.primary : AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: const Text(
              'Manage your interaction with this user',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
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
