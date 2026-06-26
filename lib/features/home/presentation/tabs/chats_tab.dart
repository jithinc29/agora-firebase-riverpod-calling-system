import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/home/presentation/screens/search_bottom_sheet.dart';
import 'package:call_project/core/theme/app_colors.dart';
import 'package:call_project/features/home/presentation/screens/home_screen.dart';

// Import the user profile screen correctly based on its location
// It might be in profile feature or home feature, so we assume it's imported via home_screen or we provide it directly.
// In home_screen.dart it is accessed. We will rely on home_screen.dart's imports if needed, or define the exact import.
import 'package:call_project/features/home/presentation/screens/user_profile_screen.dart';

class ChatsTab extends ConsumerWidget {
  final AsyncValue<List<UserModel>> usersAsync;
  final User? currentUser;
  final UserModel user;
  final VoidCallback onPauseReels;
  final String Function(DateTime?, DateTime) formatLastSeen;

  const ChatsTab({
    super.key,
    required this.usersAsync,
    required this.currentUser,
    required this.user,
    required this.onPauseReels,
    required this.formatLastSeen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: TextField(
              readOnly: true,
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => SearchBottomSheet(
                    usersAsync: usersAsync,
                    currentUser: currentUser,
                  ),
                );
              },
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.textSecondary,
                ),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          Expanded(
            child: usersAsync.when(
              data: (users) {
                final now = DateTime.now();
                final otherUsers = users.where((u) {
                  if (u.uid == currentUser?.uid) return false;
                  if (u.displayName.trim().isEmpty) return false;
                  if (u.lastSeen == null) return false;
                  if (user.blockedUsers.contains(u.uid)) return false;
                  if (u.blockedUsers.contains(user.uid)) return false;
                  final difference = now.difference(u.lastSeen!);
                  if (difference.inDays > 7) return false;
                  return true;
                }).toList();

                otherUsers.sort((a, b) {
                  final aOnline =
                      a.isOnline && now.difference(a.lastSeen!).inMinutes < 2;
                  final bOnline =
                      b.isOnline && now.difference(b.lastSeen!).inMinutes < 2;
                  if (aOnline && !bOnline) return -1;
                  if (!aOnline && bOnline) return 1;
                  return b.lastSeen!.compareTo(a.lastSeen!);
                });

                if (otherUsers.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => ref.refresh(allUsersProvider.future),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 100),
                        Center(
                          child: Text(
                            'No active users found',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.refresh(allUsersProvider.future),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 20, bottom: 78),
                    itemCount: otherUsers.length,
                    itemBuilder: (context, index) {
                      return _buildUserTile(
                        context,
                        otherUsers[index],
                        user,
                        now,
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => RefreshIndicator(
                onRefresh: () async => ref.refresh(allUsersProvider.future),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 100),
                    Center(child: Text('Error: $e')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(
    BuildContext context,
    UserModel otherUser,
    UserModel currentUserObj,
    DateTime now,
  ) {
    final isActuallyOnline =
        otherUser.isOnline && now.difference(otherUser.lastSeen!).inMinutes < 2;
    final isFollowing = currentUserObj.following.contains(otherUser.uid);
    final followBack = otherUser.following.contains(currentUserObj.uid);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        onTap: () {
          onPauseReels();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UserProfileScreen(user: otherUser),
            ),
          );
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Stack(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                ),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: otherUser.photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: otherUser.photoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: Colors.black12),
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.error),
                      )
                    : Center(
                        child: Text(
                          otherUser.displayName.isNotEmpty
                              ? otherUser.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
              ),
            ),
            if (isActuallyOnline)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          otherUser.displayName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Row(
          children: [
            Text(
              isActuallyOnline
                  ? 'Online now'
                  : formatLastSeen(otherUser.lastSeen, now),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            if (isFollowing && followBack) ...[
              const SizedBox(width: 8),
              const Icon(Icons.verified, color: AppColors.primary, size: 14),
            ] else if (isFollowing) ...[
              const SizedBox(width: 8),
              const Text(
                '• Following',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: Colors.black12,
          size: 20,
        ),
      ),
    );
  }
}
