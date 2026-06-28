import 'package:call_project/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:call_project/features/users/data/repository/user_repository.dart';
// For AppColors and userDetailsProvider
import 'package:call_project/features/auth/repository/auth_repository.dart'; // For currentUserDataProvider
import 'package:call_project/core/widgets/custom_avatar.dart';

class FollowRequestsScreen extends ConsumerWidget {
  final String currentUserId;
  final List<String> pendingRequests;

  const FollowRequestsScreen({
    super.key,
    required this.currentUserId,
    required this.pendingRequests,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allUsersAsync = ref.watch(allUsersProvider);
    final userAsync = ref.watch(currentUserDataProvider);

    return userAsync.when(
      data: (currentUser) {
        if (currentUser == null) {
          return const Scaffold(body: Center(child: Text('User not found')));
        }
        final reactivePendingRequests = currentUser.pendingFollowRequests;

        return allUsersAsync.when(
          data: (allUsers) {
            final registeredUids = allUsers.map((u) => u.uid).toSet();
            final activeReceivedUids = reactivePendingRequests
                .where((uid) => registeredUids.contains(uid))
                .toList();

            final activeSentUids = allUsers
                .where((u) => u.pendingFollowRequests.contains(currentUserId))
                .map((u) => u.uid)
                .toList();

            return DefaultTabController(
              length: 2,
              child: Scaffold(
                backgroundColor: const Color(0xFFF8FAFC),
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  centerTitle: true,
                  leading: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Color(0xFF0F172A),
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: const Text(
                    'Follow Requests',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  bottom: const TabBar(
                    indicatorColor: Color(0xFF6366F1),
                    labelColor: Color(0xFF6366F1),
                    unselectedLabelColor: Color(0xFF64748B),
                    labelStyle: TextStyle(fontWeight: FontWeight.bold),
                    tabs: [
                      Tab(text: 'Received'),
                      Tab(text: 'Sent'),
                    ],
                  ),
                ),
                body: TabBarView(
                  children: [
                    _buildRequestsList(
                      context,
                      ref,
                      activeReceivedUids,
                      isReceived: true,
                    ),
                    _buildRequestsList(
                      context,
                      ref,
                      activeSentUids,
                      isReceived: false,
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (e, st) => Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: Center(child: Text('Error: $e')),
          ),
        );
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildRequestsList(
    BuildContext context,
    WidgetRef ref,
    List<String> uids, {
    required bool isReceived,
  }) {
    if (uids.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isReceived ? Icons.mail_outline_rounded : Icons.send_rounded,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              isReceived ? 'No pending requests' : 'No sent requests',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: uids.length,
      itemBuilder: (context, index) {
        final uid = uids[index];
        final userAsync = ref.watch(userDetailsProvider(uid));

        return userAsync.when(
          data: (user) {
            if (user == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 0,
                ),
                leading: CustomAvatar(
radius: 26,
photoUrl: user.photoUrl,
),
                title: Text(
                  user.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  '@${user.displayName.toLowerCase().replaceAll(' ', '_')}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                trailing: isReceived
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            onPressed: () => ref
                                .read(userRepositoryProvider)
                                .acceptFollowRequest(currentUserId, uid),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Confirm',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () {
                              ref
                                  .read(userRepositoryProvider)
                                  .updateUserProfile(currentUserId, {
                                    'pendingFollowRequests':
                                        FieldValue.arrayRemove([uid]),
                                  });
                            },
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Delete',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      )
                    : OutlinedButton(
                        onPressed: () {
                          ref.read(userRepositoryProvider).updateUserProfile(
                            uid,
                            {
                              'pendingFollowRequests': FieldValue.arrayRemove([
                                currentUserId,
                              ]),
                            },
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Requested',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => const SizedBox.shrink(),
        );
      },
    );
  }
}
