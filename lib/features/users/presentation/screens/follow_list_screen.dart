import 'package:call_project/features/auth/repository/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:call_project/features/users/data/repository/user_repository.dart';
import 'package:call_project/features/users/presentation/screens/user_profile_screen.dart';
import 'package:call_project/features/chat/presentation/screens/chat_screen.dart';
import 'package:call_project/features/profile/presentation/screens/profile_screen.dart';
import 'package:call_project/core/theme/app_colors.dart';
import 'package:shimmer/shimmer.dart';

class FollowListScreen extends ConsumerStatefulWidget {
  final String title;
  final List<String> uids;
  const FollowListScreen({super.key, required this.title, required this.uids});

  @override
  ConsumerState<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends ConsumerState<FollowListScreen> {
  bool _isTransitioning = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) {
        setState(() {
          _isTransitioning = false;
        });
      }
    });
  }

  Widget _buildShimmerItem() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 120,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 80,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 80,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allUsersAsync = ref.watch(allUsersProvider);
    final currentUserData = ref.watch(currentUserDataProvider);
    final currentUser = currentUserData.asData?.value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: allUsersAsync.when(
        data: (allUsers) {
          if (_isTransitioning) {
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              itemCount: 8,
              itemBuilder: (context, index) => _buildShimmerItem(),
            );
          }

          final registeredUids = allUsers.map((u) => u.uid).toSet();
          final activeUids = widget.uids
              .where((uid) => registeredUids.contains(uid))
              .toList();

          return activeUids.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_alt_outlined,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No users in ${widget.title}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  itemCount: activeUids.length,
                  itemBuilder: (context, index) {
                    final uid = activeUids[index];
                    final userAsync = ref.watch(userDetailsProvider(uid));

                    return userAsync.when(
                      data: (user) {
                        if (user == null) return const SizedBox.shrink();

                        final isFollowing =
                            currentUser?.following.contains(user.uid) ?? false;
                        final hasRequested = user.pendingFollowRequests
                            .contains(currentUser?.uid);


                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            onTap: () {
                              if (currentUser != null && user.uid == currentUser.uid) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ProfileScreen(),
                                  ),
                                );
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserProfileScreen(user: user),
                                  ),
                                );
                              }
                            },
                            leading: CircleAvatar(
                              radius: 26,
                                  backgroundColor: AppColors.primary
                                      .withOpacity(0.1),
                                  backgroundImage:
                                      user.photoUrl != null &&
                                          user.photoUrl!.isNotEmpty
                                      ? CachedNetworkImageProvider(
                                          user.photoUrl!,
                                        )
                                      : null,
                                  child: (user.photoUrl == null || user.photoUrl!.isEmpty)
                                      ? const Icon(
                                          Icons.person,
                                          color: AppColors.primary,
                                          size: 30,
                                        )
                                      : null,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    user.displayName.toLowerCase().replaceAll(
                                      ' ',
                                      '',
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),

                              ],
                            ),
                            subtitle: Text(
                              user.displayName,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: (currentUser != null && user.uid == currentUser.uid)
                                ? const SizedBox.shrink()
                                : isFollowing
                                    ? ElevatedButton(
                                        onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ChatScreen(receiver: user),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.surfaceLight,
                                      foregroundColor: AppColors.textPrimary,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      minimumSize: const Size(0, 32),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: const Text(
                                      'Message',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : ElevatedButton(
                                    onPressed: () {
                                      if (currentUser == null) return;
                                      if (hasRequested) {
                                        ref
                                            .read(userRepositoryProvider)
                                            .cancelFollowRequest(
                                              currentUser.uid,
                                              user.uid,
                                            );
                                      } else {
                                        ref
                                            .read(userRepositoryProvider)
                                            .sendFollowRequest(
                                              currentUser.uid,
                                              user.uid,
                                            );
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                      ),
                                      minimumSize: const Size(0, 32),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: Text(
                                      hasRequested ? 'Requested' : 'Follow',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                          ),
                        );
                      },
                      loading: () => _buildShimmerItem(),
                      error: (e, st) => const SizedBox.shrink(),
                    );
                  },
                );
        },
        loading: () => ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          itemCount: 8,
          itemBuilder: (context, index) => _buildShimmerItem(),
        ),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
