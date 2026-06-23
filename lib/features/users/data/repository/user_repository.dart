import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:call_project/core/providers/firebase_providers.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/core/config/agora_config.dart';
import 'package:call_project/features/notifications/models/notification_model.dart';
import 'package:uuid/uuid.dart';

part 'user_repository.g.dart';

class UserRepository {
  final FirebaseFirestore _firestore;

  UserRepository({required FirebaseFirestore firestore}) : _firestore = firestore;

  Future<List<UserModel>> getAllUsers() async {
    final snapshot = await _firestore.collection('users').get();
    return snapshot.docs
        .map((doc) => UserModel.fromMap(doc.data()))
        .toList();
  }

  Stream<UserModel?> getUser(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromMap(doc.data()!);
    });
  }

  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    await _firestore.collection('users').doc(uid).update(data);
  }

  // --- Social Logic ---

  Future<void> sendFollowRequest(String currentUid, String targetUid) async {
    final currentDoc = await _firestore.collection('users').doc(currentUid).get();
    final currentName = currentDoc.data()?['displayName'] ?? 'Someone';
    final currentPhoto = currentDoc.data()?['photoUrl'];

    await _firestore.collection('users').doc(targetUid).update({
      'pendingFollowRequests': FieldValue.arrayUnion([currentUid]),
    });

    // Add In-App Notification
    final notification = NotificationModel(
      id: const Uuid().v4(),
      receiverId: targetUid,
      senderId: currentUid,
      senderName: currentName,
      senderPhotoUrl: currentPhoto,
      title: 'New Follow Request',
      body: '$currentName wants to follow you',
      type: NotificationType.followRequest,
      timestamp: DateTime.now(),
    );

    await _firestore
        .collection('users')
        .doc(targetUid)
        .collection('notifications')
        .doc(notification.id)
        .set(notification.toMap());

    // Send Push Notification
    final targetDoc = await _firestore.collection('users').doc(targetUid).get();
    final targetToken = targetDoc.data()?['fcmToken'];
    if (targetToken != null) {
      _sendPushNotification(
        token: targetToken,
        title: notification.title,
        body: notification.body,
        type: 'follow_request',
      );
    }
  }

  Future<void> cancelFollowRequest(String currentUid, String targetUid) async {
    await _firestore.collection('users').doc(targetUid).update({
      'pendingFollowRequests': FieldValue.arrayRemove([currentUid]),
    });
  }

  Future<void> acceptFollowRequest(String currentUid, String senderUid) async {
    final batch = _firestore.batch();
    
    final currentDoc = _firestore.collection('users').doc(currentUid);
    final senderDoc = _firestore.collection('users').doc(senderUid);

    // Add sender to current user's followers and remove from pending
    batch.update(currentDoc, {
      'followers': FieldValue.arrayUnion([senderUid]),
      'pendingFollowRequests': FieldValue.arrayRemove([senderUid]),
    });

    // Add current user to sender's following
    batch.update(senderDoc, {
      'following': FieldValue.arrayUnion([currentUid]),
    });

    await batch.commit();

    // Send push notification
    final senderData = await senderDoc.get();
    final senderToken = senderData.data()?['fcmToken'];
    final currentData = await currentDoc.get();
    final currentName = currentData.data()?['displayName'] ?? 'Someone';

    if (senderToken != null) {
      _sendPushNotification(
        token: senderToken,
        title: 'Follow Request Accepted',
        body: '$currentName accepted your follow request!',
        type: 'follow_accepted',
      );
    }
  }

  Future<void> unfollowUser(String currentUid, String targetUid) async {
    final batch = _firestore.batch();
    final currentDoc = _firestore.collection('users').doc(currentUid);
    final targetDoc = _firestore.collection('users').doc(targetUid);

    // Remove target from current user's following
    batch.update(currentDoc, {
      'following': FieldValue.arrayRemove([targetUid]),
    });

    // Remove current user from target's followers
    batch.update(targetDoc, {
      'followers': FieldValue.arrayRemove([currentUid]),
    });

    await batch.commit();

    // Notify the other user
    final targetData = await targetDoc.get();
    final targetToken = targetData.data()?['fcmToken'];
    final currentData = await currentDoc.get();
    final currentName = currentData.data()?['displayName'] ?? 'Someone';

    if (targetToken != null) {
      _sendPushNotification(
        token: targetToken,
        title: 'Unfollowed',
        body: '$currentName unfollowed you',
        type: 'unfollow',
      );
    }
  }

  Future<void> blockUser(String currentUid, String targetUid) async {
    final batch = _firestore.batch();
    final currentDoc = _firestore.collection('users').doc(currentUid);
    final targetDoc = _firestore.collection('users').doc(targetUid);

    batch.update(currentDoc, {
      'blockedUsers': FieldValue.arrayUnion([targetUid]),
      'following': FieldValue.arrayRemove([targetUid]),
      'followers': FieldValue.arrayRemove([targetUid]),
    });

    // Optionally also remove me from their lists
    batch.update(targetDoc, {
      'following': FieldValue.arrayRemove([currentUid]),
      'followers': FieldValue.arrayRemove([currentUid]),
    });

    await batch.commit();
  }

  Future<void> unblockUser(String currentUid, String targetUid) async {
    await _firestore.collection('users').doc(currentUid).update({
      'blockedUsers': FieldValue.arrayRemove([targetUid]),
    });
  }

  void _sendPushNotification({
    required String token,
    required String title,
    required String body,
    required String type,
  }) {
    // Using the existing Vercel signaling endpoint as a generic notification gateway
    http.post(
      Uri.parse('${AgoraConfig.tokenBaseUrl}/api/initiate_call'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        't': type,
        'title': title,
        'body': body,
        'receiverToken': token,
      }),
    ).timeout(const Duration(seconds: 10)).catchError((e) => http.Response('error', 500));
  }
}

@riverpod
UserRepository userRepository(Ref ref) {
  return UserRepository(firestore: ref.watch(firestoreProvider));
}

@riverpod
Future<List<UserModel>> allUsers(Ref ref) {
  return ref.watch(userRepositoryProvider).getAllUsers();
}

@riverpod
Stream<UserModel?> userDetails(Ref ref, String uid) {
  return ref.watch(userRepositoryProvider).getUser(uid);
}
