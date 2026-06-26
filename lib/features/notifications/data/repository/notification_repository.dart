import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:call_project/core/providers/firebase_providers.dart';
import 'package:call_project/features/notifications/models/notification_model.dart';

part 'notification_repository.g.dart';

class NotificationRepository {
  final FirebaseFirestore _firestore;

  NotificationRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  Stream<List<NotificationModel>> getNotifications(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => NotificationModel.fromMap(doc.data()))
              .toList();
        });
  }

  Future<void> addNotification(NotificationModel notification) async {
    await _firestore
        .collection('users')
        .doc(notification.receiverId)
        .collection('notifications')
        .doc(notification.id)
        .set(notification.toMap());
  }

  Future<void> markAsRead(String uid, String notificationId) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  Future<void> markAllAsRead(String uid) async {
    final batch = _firestore.batch();
    final notifications = await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .get();

    for (var doc in notifications.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
  }
}

@riverpod
NotificationRepository notificationRepository(Ref ref) {
  return NotificationRepository(firestore: ref.watch(firestoreProvider));
}

@riverpod
Stream<List<NotificationModel>> notifications(Ref ref, String uid) {
  return ref.watch(notificationRepositoryProvider).getNotifications(uid);
}

@riverpod
Stream<int> unreadNotificationsCount(Ref ref, String uid) {
  return ref
      .watch(notificationRepositoryProvider)
      .getNotifications(uid)
      .map((list) => list.where((n) => !n.isRead).length);
}
