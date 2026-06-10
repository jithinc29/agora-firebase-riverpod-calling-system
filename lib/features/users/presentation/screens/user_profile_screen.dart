import 'dart:ui';
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

class AppColors {
  static const primary = Color(0xFF6366F1); // Indigo
  static const secondary = Color(0xFFA855F7); // Purple
  static const background = Color(0xFFF8FAFC); // Slate Light
  static const success = Color(0xFF10B981); // Emerald
  static const error = Color(0xFFEF4444); // Rose
  static const textPrimary = Color(0xFF0F172A); // Midnight
  static const textSecondary = Color(0xFF64748B); // Slate Muted
}

class UserProfileScreen extends ConsumerWidget {
  final UserModel user;
  const UserProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userDetailsProvider(user.uid));
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

                final isFollowing = currentUser.following.contains(targetUser.uid);
                final hasRequested = targetUser.pendingFollowRequests.contains(
                  currentUser.uid,
                );
                final isBlocked = currentUser.blockedUsers.contains(targetUser.uid);
                final canInteract =
                    isFollowing && targetUser.following.contains(currentUser.uid);

                return Scaffold(
                  backgroundColor: AppColors.background,
                  appBar: AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Column(
                      children: [
                        // Compact Profile Header Card
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

                        // Bento 3: Quick Action Buttons (Chat, Call, Video)
                        if (!isBlocked) ...[
                          if (canInteract)
                            _buildActionsBento(context, ref, currentUser, targetUser)
                          else
                            _buildLockedBento(),
                          const SizedBox(height: 16),
                        ],

                        // Bento 4: Privacy Settings
                        _buildPrivacyBento(context, ref, currentUser.uid, targetUser.uid, isBlocked),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
              error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
            );
          },
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
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
    final isActuallyOnline =
        targetUser.isOnline &&
        targetUser.lastSeen != null &&
        now.difference(targetUser.lastSeen!).inMinutes < 2;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              Hero(
                tag: 'profile_${targetUser.uid}',
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    image: targetUser.photoUrl != null
                        ? DecorationImage(
                            image: NetworkImage(targetUser.photoUrl!),
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
              const SizedBox(width: 16),
              // User Info Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      targetUser.displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
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
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Clickable Stats Row (Twitter style)
                    Row(
                      children: [
                        GestureDetector(
                          onTap: isFollowing
                              ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FollowListScreen(title: 'Followers', uids: activeFollowers),
                                    ),
                                  )
                              : null,
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                              children: [
                                TextSpan(
                                  text: '${activeFollowers.length} ',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                                const TextSpan(text: 'Followers'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('•', style: TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: isFollowing
                              ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FollowListScreen(title: 'Following', uids: activeFollowing),
                                    ),
                                  )
                              : null,
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                              children: [
                                TextSpan(
                                  text: '${activeFollowing.length} ',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                                const TextSpan(text: 'Following'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Compact Follow Button inside header card
          SizedBox(
            width: double.infinity,
            height: 44,
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
                elevation: isFollowing ? 0 : 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isFollowing
                      ? BorderSide(color: AppColors.primary.withValues(alpha: 0.2), width: 1)
                      : BorderSide.none,
                ),
                shadowColor: AppColors.primary.withValues(alpha: 0.1),
              ),
              child: Text(
                isFollowing
                    ? 'Following'
                    : (hasRequested ? 'Request Sent' : 'Follow'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
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
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
              _buildInteractionCircle(
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
              _buildInteractionCircle(
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
          ),
        ],
      ),
    );
  }

  Widget _buildLockedBento() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_rounded, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Features Locked',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Follow each other to unlock chat and calls.',
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

  Widget _buildPrivacyBento(
    BuildContext context,
    WidgetRef ref,
    String currentUid,
    String targetUid,
    bool isBlocked,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: () => _handleBlock(context, ref, currentUid, targetUid, isBlocked),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: (isBlocked ? AppColors.primary : AppColors.error).withValues(alpha: 0.08),
            child: Icon(
              isBlocked ? Icons.undo_rounded : Icons.block_rounded,
              color: isBlocked ? AppColors.primary : AppColors.error,
              size: 18,
            ),
          ),
          title: Text(
            isBlocked ? 'Unblock User' : 'Block User',
            style: TextStyle(
              color: isBlocked ? AppColors.primary : AppColors.error,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          subtitle: const Text(
            'Manage your interaction with this user',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary,
            size: 20,
          ),
        ),
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
