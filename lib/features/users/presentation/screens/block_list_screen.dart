import 'package:call_project/features/auth/repository/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:call_project/features/users/data/repository/user_repository.dart';
import 'package:call_project/core/providers/firebase_providers.dart';

class BlockListScreen extends ConsumerWidget {
  const BlockListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserAsync = ref.watch(currentUserDataProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: const Text(
          'Blocked Users',
          style: TextStyle(
            color: Color(0xFF1A1C1E),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1C1E)),
      ),
      body: currentUserAsync.when(
        data: (user) {
          if (user == null || user.blockedUsers.isEmpty) {
            return const Center(
              child: Text(
                'No blocked users',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: user.blockedUsers.length,
            itemBuilder: (context, index) {
              final blockedUid = user.blockedUsers[index];
              final blockedUserAsync = ref.watch(
                userDetailsProvider(blockedUid),
              );

              return blockedUserAsync.when(
                data: (blockedUser) {
                  if (blockedUser == null) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey.shade100,
                        backgroundImage: blockedUser.photoUrl != null
                            ? NetworkImage(blockedUser.photoUrl!)
                            : null,
                        child: blockedUser.photoUrl == null
                            ? const Icon(Icons.person, color: Colors.grey)
                            : null,
                      ),
                      title: Text(
                        blockedUser.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: TextButton(
                        onPressed: () {
                          ref
                              .read(userRepositoryProvider)
                              .unblockUser(user.uid, blockedUid);
                        },
                        child: const Text(
                          'Unblock',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  );
                },
                loading: () => const ListTile(title: LinearProgressIndicator()),
                error: (e, st) => ListTile(title: Text('Error: $e')),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
