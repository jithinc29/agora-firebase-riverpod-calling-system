import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:call_project/core/providers/firebase_providers.dart';
import 'package:call_project/features/call/domain/entities/call_entity.dart';
import 'package:call_project/core/config/agora_config.dart';
import 'package:call_project/features/notifications/models/notification_model.dart';
import 'package:uuid/uuid.dart';
import 'package:call_project/features/auth/models/user_model.dart';

part 'call_repository.g.dart';

class CallRepository {
  final FirebaseFirestore _firestore;

  CallRepository({
    required FirebaseFirestore firestore,
  })  : _firestore = firestore;

  Stream<QuerySnapshot> incomingCallStream(String receiverId) {
    return _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: receiverId)
        .snapshots();
  }

  Stream<DocumentSnapshot> callStream(String channelId) {
    return _firestore.collection('calls').doc(channelId).snapshots();
  }

  Future<String?> getAgoraToken(String channelName, int uid) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${AgoraConfig.tokenBaseUrl}/api/token?channelName=$channelName&uid=$uid&role=publisher',
        ),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['token'];
      } else {
        debugPrint('Failed to load token: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching Agora token: $e');
      return null;
    }
  }

  Future<void> makeCall(CallEntity call) async {
    try {
      debugPrint('Initiating call signaling for channel: ${call.channelId}');
      
      // 1 & 2 & 3. Run Firestore write and Vercel signaling in PARALLEL
      // This significantly reduces the delay for the receiver to get the signal.
      final Future<void> firestoreFuture = _firestore.collection('calls').doc(call.channelId).set({
        ...call.toMap(),
        'status': 'dialing',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

      // 2. Fetch the receiver's FCM token (Need this for Vercel)
      // We do this first as it's a prerequisite for Vercel
      final receiverDoc = await _firestore.collection('users').doc(call.receiverId).get();
      final receiverToken = receiverDoc.data()?['fcmToken'];

      final payload = {
        'cid': call.channelId,
        'cn': call.callerName,
        'uid': call.callerId,
        'ac': call.isAudioCall.toString(),
        's': 'dialing',
        't': 'call',
        'createdAt': DateTime.now().millisecondsSinceEpoch.toString(),
        'receiverToken': receiverToken,
      };

      debugPrint('DEBUG: Sending signaling payload to Vercel in parallel: $payload');
      
      final Future<void> vercelFuture = http.post(
        Uri.parse('${AgoraConfig.tokenBaseUrl}/api/initiate_call'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 15)).then((response) {
         debugPrint('DEBUG: Vercel signaling response: ${response.statusCode}');
      }).catchError((e) {
         debugPrint('DEBUG: Vercel signaling FAILED: $e');
      });

      // Wait for both to complete
      await Future.wait([firestoreFuture, vercelFuture]);
      debugPrint('Call initiation signaling completed (Parallel).');

    } catch (e) {
      debugPrint('Error during makeCall signaling: $e');
    }
  }

  Future<void> endCall(String channelId) async {
    await updateCallStatus(channelId, 'ended');
  }

  Future<void> updateCallStatus(String channelId, String status) async {
    try {
      // 0. Check current status to prevent loops
      final currentDoc = await _firestore.collection('calls').doc(channelId).get();
      if (currentDoc.exists && currentDoc.data()?['status'] == status) {
        debugPrint('Call $channelId status is already $status. Skipping update.');
        return;
      }

      // 1. Update Firestore
      await _firestore.collection('calls').doc(channelId).set({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. SIGNAL VERCEL (Critical for dismissing KILLED/BACKGROUND apps)
      // Only signal if the call is being terminated
      if (status == 'ended' || status == 'cancelled' || status == 'declined' || status == 'timed_out') {
        final callDoc = await _firestore.collection('calls').doc(channelId).get();
        if (!callDoc.exists) return;

        final callData = callDoc.data() as Map<String, dynamic>;
        
        // --- Added Missed Call Notification Logic ---
        if (status == 'timed_out' || status == 'declined' || status == 'cancelled') {
           final receiverId = callData['receiverId'];
           final callerId = callData['callerId'];
           final callerName = callData['callerName'];
           
           // If I was the receiver and I missed it
           final notification = NotificationModel(
             id: const Uuid().v4(),
             receiverId: receiverId,
             senderId: callerId,
             senderName: callerName,
             title: 'Missed Call',
             body: 'You missed a call from $callerName',
             type: NotificationType.missedCall,
             timestamp: DateTime.now(),
           );

           await _firestore
               .collection('users')
               .doc(receiverId)
               .collection('notifications')
               .doc(notification.id)
               .set(notification.toMap());
        }
        // ---------------------------------------------

        // SANITIZE FOR JSON: Convert Timestamp to int
        final sanitizedData = <String, dynamic>{};
        callData.forEach((key, value) {
          if (value is Timestamp) {
            sanitizedData[key] = value.millisecondsSinceEpoch;
          } else {
            sanitizedData[key] = value;
          }
        });

        final receiverId = callData['receiverId'];
        
        // Fetch the receiver's token
        final receiverDoc = await _firestore.collection('users').doc(receiverId).get();
        final receiverData = receiverDoc.data();
        final receiverToken = receiverData?['fcmToken'];

        if (receiverToken != null) {
          final payload = {
            'cid': channelId,
            's': status,
            't': 'call',
            'receiverToken': receiverToken,
          };
          
          debugPrint('DEBUG: Sending $status signal to Vercel for dismissal...');
          http.post(
            Uri.parse('${AgoraConfig.tokenBaseUrl}/api/initiate_call'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          ).timeout(const Duration(seconds: 10)).catchError((e) {
            debugPrint('Vercel post failed: $e');
            return http.Response('err', 500);
          });
        }
      }
    } catch (e) {
      debugPrint('Error in updateCallStatus: $e');
    }
  }

  Future<void> updateCallData(String channelId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('calls').doc(channelId).set(
            data,
            SetOptions(merge: true),
          );
    } catch (e) {
      debugPrint('Error in updateCallData: $e');
    }
  }
}

@riverpod
CallRepository callRepository(Ref ref) {
  return CallRepository(
    firestore: ref.watch(firestoreProvider),
  );
}

@riverpod
Stream<QuerySnapshot> incomingCallStream(Ref ref, String receiverId) {
  return ref.watch(callRepositoryProvider).incomingCallStream(receiverId);
}

@riverpod
Stream<DocumentSnapshot> callStream(Ref ref, String channelId) {
  return ref.watch(callRepositoryProvider).callStream(channelId);
}
