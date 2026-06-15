import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:call_project/features/users/data/repository/user_repository.dart';
import 'package:call_project/features/profile/presentation/screens/profile_screen.dart'; // For AppColors and userDetailsProvider
import 'package:call_project/features/auth/repository/auth_repository.dart'; // For currentUserDataProvider

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
        if (currentUser == null) return const Scaffold(body: Center(child: Text('User not found')));
        final reactivePendingRequests = currentUser.pendingFollowRequests;

        return allUsersAsync.when(
          data: (allUsers) {
            final registeredUids = allUsers.map((u) => u.uid).toSet();
            final activeReceivedUids = reactivePendingRequests.where((uid) => registeredUids.contains(uid)).toList();
            
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
                _buildRequestsList(context, ref, activeReceivedUids, isReceived: true),
                _buildRequestsList(context, ref, activeSentUids, isReceived: false),
              ],
            ),
          ),
        );
          },
          loading: () => const Scaffold(backgroundColor: Color(0xFFF8FAFC), body: Center(child: CircularProgressIndicator())),
          error: (e, st) => Scaffold(backgroundColor: const Color(0xFFF8FAFC), body: Center(child: Text('Error: $e'))),
        );
      },
      loading: () => const Scaffold(backgroundColor: Color(0xFFF8FAFC), body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(backgroundColor: const Color(0xFFF8FAFC), body: Center(child: Text('Error: $e'))),
    );
  }

  Widget _buildRequestsList(BuildContext context, WidgetRef ref, List<String> uids, {required bool isReceived}) {
    if (uids.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isReceived ? Icons.mail_outline_rounded : Icons.send_rounded, size: 48, color: Colors.grey.shade400),
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
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.04),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  radius: 20,
                  backgroundImage: user.photoUrl != null
                      ? CachedNetworkImageProvider(
                          user.photoUrl!,
                        )
                      : null,
                  backgroundColor: AppColors.primary.withValues(
                    alpha: 0.1,
                  ),
                  child: user.photoUrl == null
                      ? Text(
                          user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 18),
                        )
                      : null,
                ),
                title: Text(
                  user.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: isReceived
                      ? [
                          IconButton(
                            icon: const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.success,
                            ),
                            onPressed: () => ref
                                .read(userRepositoryProvider)
                                .acceptFollowRequest(currentUserId, uid),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.cancel_rounded,
                              color: AppColors.error,
                            ),
                            onPressed: () {
                              ref
                                  .read(userRepositoryProvider)
                                  .updateUserProfile(currentUserId, {
                                    'pendingFollowRequests':
                                        FieldValue.arrayRemove([uid]),
                                  });
                            },
                          ),
                        ]
                      : [
                          OutlinedButton(
                            onPressed: () {
                              ref
                                  .read(userRepositoryProvider)
                                  .updateUserProfile(uid, {
                                    'pendingFollowRequests':
                                        FieldValue.arrayRemove([currentUserId]),
                                  });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                ),
              ),
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (err, _) => const SizedBox.shrink(),
        );
      },
    );
  }
}
