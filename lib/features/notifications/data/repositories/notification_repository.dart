import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:call_project/core/providers/firebase_providers.dart';

part 'notification_repository.g.dart';

class NotificationRepository {
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  NotificationRepository({
    required FirebaseMessaging messaging,
    required FirebaseFirestore firestore,
  })  : _messaging = messaging,
        _firestore = firestore;

  Future<void> requestPermissions() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  Future<void> updateToken(String uid) async {
    final token = await getToken();
    if (token != null) {
      await _firestore.collection('users').doc(uid).set({
        'fcmToken': token,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
    }
  }

  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;
}

@riverpod
NotificationRepository notificationRepository(Ref ref) {
  return NotificationRepository(
    messaging: FirebaseMessaging.instance,
    firestore: ref.watch(firestoreProvider),
  );
}
