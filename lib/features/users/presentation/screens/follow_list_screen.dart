import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:call_project/features/users/data/repository/user_repository.dart';
import 'package:call_project/features/users/presentation/screens/user_profile_screen.dart';

class FollowListScreen extends ConsumerWidget {
  final String title;
  final List<String> uids;
  const FollowListScreen({super.key, required this.title, required this.uids});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allUsersAsync = ref.watch(allUsersProvider);

    return allUsersAsync.when(
      data: (allUsers) {
        final registeredUids = allUsers.map((u) => u.uid).toSet();
        final activeUids = uids
            .where((uid) => registeredUids.contains(uid))
            .toList();

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC), // AppColors.background
          appBar: AppBar(
            title: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF0F172A), // AppColors.textPrimary
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
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
          ),
          body: activeUids.isEmpty
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
                        'No users in $title',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
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
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => UserProfileScreen(user: user),
                                ),
                              );
                            },
                            leading: CircleAvatar(
                              radius: 26,
                              backgroundColor: const Color(
                                0xFF6366F1,
                              ).withOpacity(0.1),
                              backgroundImage:
                                  user.photoUrl != null &&
                                      user.photoUrl!.isNotEmpty
                                  ? CachedNetworkImageProvider(user.photoUrl!)
                                  : null,
                              child:
                                  (user.photoUrl == null ||
                                      user.photoUrl!.isEmpty)
                                  ? Text(
                                      user.displayName.isNotEmpty
                                          ? user.displayName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Color(0xFF6366F1),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              user.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            subtitle: Text(
                              '@${user.displayName.toLowerCase().replaceAll(' ', '_')}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            trailing: OutlinedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        UserProfileScreen(user: user),
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                minimumSize: const Size(0, 32),
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'View',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (e, st) => const SizedBox.shrink(),
                    );
                  },
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
}
