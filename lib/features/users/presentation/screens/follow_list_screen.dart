import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        final activeUids = uids.where((uid) => registeredUids.contains(uid)).toList();

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FE),
          appBar: AppBar(
            title: Text(title, style: const TextStyle(color: Color(0xFF1A1C1E), fontWeight: FontWeight.bold)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Color(0xFF1A1C1E)),
          ),
          body: activeUids.isEmpty
              ? Center(child: Text('No users in $title', style: const TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: activeUids.length,
                  itemBuilder: (context, index) {
                    final uid = activeUids[index];
                    final userAsync = ref.watch(userDetailsProvider(uid));

                    return userAsync.when(
                      data: (user) {
                        if (user == null) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ListTile(
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(user: user)));
                            },
                            leading: CircleAvatar(
                              radius: 25,
                              backgroundColor: Colors.purple.shade50,
                              backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                              child: user.photoUrl == null
                                  ? Text(user.displayName[0].toUpperCase(), style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold))
                                  : null,
                            ),
                            title: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          ),
                        );
                      },
                      loading: () => const ListTile(title: LinearProgressIndicator()),
                      error: (e, st) => ListTile(title: Text('Error: $e')),
                    );
                  },
                ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }
}
