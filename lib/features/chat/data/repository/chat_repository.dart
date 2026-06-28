import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:call_project/core/providers/firebase_providers.dart';
import 'package:call_project/features/chat/models/message_model.dart';
import 'package:call_project/features/notifications/models/notification_model.dart';
import 'package:call_project/core/config/agora_config.dart';
import 'package:uuid/uuid.dart';

part 'chat_repository.g.dart';

class ChatRepository {
  final FirebaseFirestore _firestore;

  ChatRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  String _getChatRoomId(String uid1, String uid2) {
    List<String> ids = [uid1, uid2];
    ids.sort();
    return ids.join('_');
  }

  Stream<List<MessageModel>> getMessages(
    String currentUserId,
    String receiverId,
  ) {
    final chatRoomId = _getChatRoomId(currentUserId, receiverId);
    return _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => MessageModel.fromMap(doc.data()))
              .toList();
        });
  }

  Future<void> sendMessage(MessageModel message) async {
    final chatRoomId = _getChatRoomId(message.senderId, message.receiverId);

    // Update the message in the sub-collection
    await _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc(message.id)
        .set(message.toMap());

    // Update the last message and timestamp in the main chat document for the inbox view
    await _firestore.collection('chats').doc(chatRoomId).set({
      'lastMessage': message.content,
      'lastMessageTimestamp': message.timestamp.millisecondsSinceEpoch,
      'lastMessageSenderId': message.senderId,
      'users': [message.senderId, message.receiverId],
    }, SetOptions(merge: true));

    // Send Push Notification and add In-App Notification
    final senderDoc = await _firestore
        .collection('users')
        .doc(message.senderId)
        .get();
    final senderName = senderDoc.data()?['displayName'] ?? 'Someone';
    final senderPhoto = senderDoc.data()?['photoUrl'];

    final receiverDoc = await _firestore
        .collection('users')
        .doc(message.receiverId)
        .get();
    final receiverToken = receiverDoc.data()?['fcmToken'];

    if (receiverToken != null) {
      // Send via Vercel gateway
      http
          .post(
            Uri.parse('${AgoraConfig.tokenBaseUrl}/api/initiate_call'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              't': 'message',
              'title': senderName,
              'body': message.content,
              'receiverToken': receiverToken,
            }),
          )
          .timeout(const Duration(seconds: 10))
          // ignore: invalid_return_type_for_catch_error
          .catchError((e) => null);
    }

    // Add In-App Notification (optional, but requested for "received messages")
    final notification = NotificationModel(
      id: const Uuid().v4(),
      receiverId: message.receiverId,
      senderId: message.senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhoto,
      title: 'New Message',
      body: message.content,
      type: NotificationType.message,
      timestamp: DateTime.now(),
    );

    await _firestore
        .collection('users')
        .doc(message.receiverId)
        .collection('notifications')
        .doc(notification.id)
        .set(notification.toMap());
  }

  Stream<int> getUnreadMessagesCount(String currentUserId, String otherUserId) {
    final chatRoomId = _getChatRoomId(currentUserId, otherUserId);
    return _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .where('senderId', isEqualTo: otherUserId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> markMessagesAsRead(
    String currentUserId,
    String otherUserId,
  ) async {
    final chatRoomId = _getChatRoomId(currentUserId, otherUserId);
    final messages = await _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .where('senderId', isEqualTo: otherUserId)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (var doc in messages.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  Future<void> deleteMessage(
    String currentUserId,
    String otherUserId,
    String messageId,
  ) async {
    final chatRoomId = _getChatRoomId(currentUserId, otherUserId);
    await _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }
}

@riverpod
ChatRepository chatRepository(Ref ref) {
  return ChatRepository(firestore: ref.watch(firestoreProvider));
}

@riverpod
Stream<List<MessageModel>> chatMessages(
  Ref ref, {
  required String currentUserId,
  required String receiverId,
}) {
  return ref
      .watch(chatRepositoryProvider)
      .getMessages(currentUserId, receiverId);
}

@riverpod
Stream<int> unreadChatMessagesCount(
  Ref ref, {
  required String currentUserId,
  required String otherUserId,
}) {
  return ref
      .watch(chatRepositoryProvider)
      .getUnreadMessagesCount(currentUserId, otherUserId);
}
