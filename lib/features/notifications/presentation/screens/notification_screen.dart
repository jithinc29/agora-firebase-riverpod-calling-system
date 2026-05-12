import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:call_project/features/notifications/data/repository/notification_repository.dart';
import 'package:call_project/features/notifications/models/notification_model.dart';
import 'package:call_project/core/providers/firebase_providers.dart';
import 'package:intl/intl.dart';

class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(firebaseAuthProvider).currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Please login')));

    final notificationsAsync = ref.watch(notificationsProvider(user.uid));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(color: Color(0xFF1A1C1E), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1C1E)),
        actions: [
          TextButton(
            onPressed: () => ref.read(notificationRepositoryProvider).markAllAsRead(user.uid),
            child: const Text('Mark all as read', style: TextStyle(color: Colors.purple)),
          ),
        ],
      ),
      body: notificationsAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('No notifications yet', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final notification = list[index];
              return _buildNotificationTile(context, ref, user.uid, notification);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildNotificationTile(BuildContext context, WidgetRef ref, String uid, NotificationModel notification) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: notification.isRead ? Colors.white : Colors.purple.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
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
          ref.read(notificationRepositoryProvider).markAsRead(uid, notification.id);
          // Add navigation based on type if needed
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: _getTypeColor(notification.type).withValues(alpha: 0.1),
              backgroundImage: notification.senderPhotoUrl != null ? NetworkImage(notification.senderPhotoUrl!) : null,
              child: notification.senderPhotoUrl == null
                  ? Icon(_getTypeIcon(notification.type), color: _getTypeColor(notification.type))
                  : null,
            ),
            if (!notification.isRead)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                notification.title,
                style: TextStyle(
                  fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            Text(
              DateFormat('HH:mm').format(notification.timestamp),
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            notification.body,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  IconData _getTypeIcon(NotificationType type) {
    switch (type) {
      case NotificationType.followRequest: return Icons.person_add;
      case NotificationType.missedCall: return Icons.phone_missed;
      case NotificationType.message: return Icons.message;
    }
  }

  Color _getTypeColor(NotificationType type) {
    switch (type) {
      case NotificationType.followRequest: return Colors.blue;
      case NotificationType.missedCall: return Colors.red;
      case NotificationType.message: return Colors.purple;
    }
  }
}
