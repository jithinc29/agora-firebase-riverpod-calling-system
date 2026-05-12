import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:call_project/features/auth/controllers/auth_controller.dart';
import 'package:call_project/features/auth/repository/auth_repository.dart';
import 'package:call_project/features/users/data/repository/user_repository.dart';
import 'package:call_project/features/call/presentation/controllers/call_controller.dart';
import 'package:call_project/features/call/presentation/screens/call_screen.dart';
import 'package:call_project/features/profile/presentation/screens/profile_screen.dart';
import 'package:call_project/features/users/presentation/screens/user_profile_screen.dart';
import 'package:call_project/features/notifications/presentation/screens/notification_screen.dart';
import 'package:call_project/features/notifications/data/repository/notification_repository.dart';
import 'package:call_project/core/navigation/navigation_service.dart';
import 'package:call_project/features/auth/models/user_model.dart';

// Unified Design System Colors (Synced across app)
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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _heartbeatTimer;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _updatePresence();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _updatePresence();
    });
  }

  void _updatePresence() async {
    if (_isDeleting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && !_isDeleting) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'isOnline': true,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
        }, SetOptions(merge: true));
      }
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserData = ref.watch(currentUserDataProvider);

    return currentUserData.when(
      data: (user) {
        if (user == null || _isDeleting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final usersAsync = ref.watch(allUsersProvider);
        final currentUser = FirebaseAuth.instance.currentUser;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Premium Header
                _buildHeader(context, ref, currentUser?.uid ?? ''),

                const SizedBox(height: 10),

                // User List Section
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5)),
                      ],
                    ),
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
                          final aOnline = a.isOnline && now.difference(a.lastSeen!).inMinutes < 2;
                          final bOnline = b.isOnline && now.difference(b.lastSeen!).inMinutes < 2;
                          if (aOnline && !bOnline) return -1;
                          if (!aOnline && bOnline) return 1;
                          return b.lastSeen!.compareTo(a.lastSeen!);
                        });

                        if (otherUsers.isEmpty) {
                          return const Center(
                            child: Text('No active users found', style: TextStyle(color: AppColors.textSecondary)),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.only(top: 20, bottom: 20),
                          itemCount: otherUsers.length,
                          itemBuilder: (context, index) {
                            return _buildUserTile(otherUsers[index], user, now);
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, st) => Center(child: Text('Error: $e')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, String uid) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Messages',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              Text(
                'Connect with friends',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
            ],
          ),
          Row(
            children: [
              _buildNotificationBadge(ref, uid),
              const SizedBox(width: 12),
              _buildHeaderAction(Icons.person_outline, () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
        ),
        child: Icon(icon, color: AppColors.primary, size: 22),
      ),
    );
  }

  Widget _buildNotificationBadge(WidgetRef ref, String uid) {
    final unreadCountAsync = ref.watch(unreadNotificationsCountProvider(uid));
    return unreadCountAsync.when(
      data: (count) => Stack(
        clipBehavior: Clip.none,
        children: [
          _buildHeaderAction(Icons.notifications_none, () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen()));
          }),
          if (count > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      loading: () => _buildHeaderAction(Icons.notifications_none, () {}),
      error: (_, __) => _buildHeaderAction(Icons.notifications_none, () {}),
    );
  }

  Widget _buildUserTile(UserModel user, UserModel currentUser, DateTime now) {
    final isActuallyOnline = user.isOnline && now.difference(user.lastSeen!).inMinutes < 2;
    final isFollowing = currentUser.following.contains(user.uid);
    final followBack = user.following.contains(currentUser.uid);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(user: user)));
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Stack(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [AppColors.primary, AppColors.secondary]),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 10)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: user.photoUrl != null 
                  ? Image.network(user.photoUrl!, fit: BoxFit.cover)
                  : Center(child: Text(user.displayName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20))),
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
          user.displayName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
        ),
        subtitle: Row(
          children: [
            Text(
              isActuallyOnline ? 'Online now' : _formatLastSeen(user.lastSeen, now),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            if (isFollowing && followBack) ...[
              const SizedBox(width: 8),
              const Icon(Icons.verified, color: AppColors.primary, size: 14),
            ] else if (isFollowing) ...[
              const SizedBox(width: 8),
              const Text('• Following', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.black12, size: 20),
      ),
    );
  }

  String _formatLastSeen(DateTime? lastSeen, DateTime now) {
    if (lastSeen == null) return 'Never';
    final difference = now.difference(lastSeen);
    if (difference.inMinutes < 60) return 'Active ${difference.inMinutes}m ago';
    if (difference.inHours < 24) return 'Active ${difference.inHours}h ago';
    return 'Active ${difference.inDays}d ago';
  }
}
