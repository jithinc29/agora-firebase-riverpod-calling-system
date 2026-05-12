import 'dart:async';
import 'package:call_project/core/navigation/navigation_service.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/call/data/repositories/call_repository.dart';
import 'package:call_project/features/call/presentation/screens/call_screen.dart';
import 'package:call_project/features/notifications/presentation/services/callkit_service.dart';
import 'package:call_project/firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notification_service.g.dart';

@riverpod
class NotificationService extends _$NotificationService {
  @override
  void build() {}

  Future<void> handleGlobalCallEvent(dynamic event) async {
    final body = Map<String, dynamic>.from(event.body as Map);
    final extra = body['extra'] != null
        ? Map<String, dynamic>.from(body['extra'] as Map)
        : null;
    final channelId = extra?['channelId'] ?? body['id'] ?? '';
    if (channelId.isEmpty) return;

    switch (event.event) {
      case Event.actionCallAccept:
        debugPrint('[GLOBAL-DEBUG] Accept event captured for $channelId. Checking status...');
        globalActiveCallId = channelId;

        // Speedy update to ongoing to prevent CallListener from re-triggering
        FirebaseFirestore.instance.collection('calls').doc(channelId).set({
          'status': 'ongoing',
          'ongoingAt': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // FRESHNESS CHECK: Verify the call is actually still valid in Firestore
        try {
          final callDoc = await FirebaseFirestore.instance
              .collection('calls')
              .doc(channelId)
              .get();
          if (!callDoc.exists) {
            debugPrint('[GLOBAL-DEBUG] Call $channelId no longer exists. Ignoring.');
            return;
          }
          final status = callDoc.data()?['status'] ?? 'ended';
          if (status == 'ended' || status == 'cancelled' || status == 'declined') {
            debugPrint('[GLOBAL-DEBUG] Call $channelId is in status $status. Ignoring.');
            return;
          }
        } catch (e) {
          debugPrint('[GLOBAL-DEBUG] Error checking call status: $e');
        }

        final guestUser = UserModel(
          uid: extra?['callerId'] ?? '',
          email: '',
          displayName: body['nameCaller'] ?? body['callerName'] ?? 'Unknown',
          isOnline: true,
        );

        // Wait for navigator to be ready
        for (int i = 0; i < 20; i++) {
          if (navigatorKey.currentState != null) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }

        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.push(
            MaterialPageRoute(
              settings: const RouteSettings(name: '/call_screen'),
              builder: (_) => CallScreen(
                channelId: channelId,
                guestUser: guestUser,
                isAudioCall: body['type']?.toString() == '0',
                isOutgoing: false,
              ),
            ),
          ).then((_) {
            if (globalActiveCallId == channelId) globalActiveCallId = null;
          });
        }
        break;

      case Event.actionCallDecline:
        debugPrint('[GLOBAL-DEBUG] Decline event captured for $channelId');
        if (globalActiveCallId == channelId) globalActiveCallId = null;

        for (int i = 0; i < 20; i++) {
          if (FirebaseAuth.instance.currentUser != null) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }
        if (FirebaseAuth.instance.currentUser != null) {
          try {
            await ref.read(callRepositoryProvider).updateCallStatus(channelId, 'declined');
          } catch (e) {
            debugPrint('[GLOBAL-DEBUG] Decline FAILED: $e');
          }
        }
        break;

      case Event.actionCallTimeout:
        debugPrint('[GLOBAL-DEBUG] Timeout event captured for $channelId');
        if (globalActiveCallId == channelId) globalActiveCallId = null;
        if (FirebaseAuth.instance.currentUser != null) {
          ref.read(callRepositoryProvider).updateCallStatus(channelId, 'timed_out');
        }
        break;

      case Event.actionCallEnded:
        debugPrint('[GLOBAL-DEBUG] Ended event captured for $channelId');
        if (globalActiveCallId == channelId) globalActiveCallId = null;
        break;

      default:
        debugPrint('[GLOBAL-DEBUG] Other event: ${event.event}');
        break;
    }
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final data = message.data;
  final String channelId = data['cid'] ?? data['channelId'] ?? data['id'] ?? '';
  final String status = data['s'] ?? data['status'] ?? 'dialing';

  if (channelId.isEmpty) {
    debugPrint('[BG-LOG] Ignoring message with empty channelId');
    return;
  }

  // 1. ULTIMATE PROTECTION: Check Firestore status FIRST before any logic
  try {
    final callDoc = await FirebaseFirestore.instance
        .collection('calls')
        .doc(channelId)
        .get(const GetOptions(source: Source.server));

    if (!callDoc.exists) {
      debugPrint('[BG-LOG] Call doc $channelId missing. Exiting.');
      return;
    }

    final currentStatus = callDoc.data()?['status'];
    if (currentStatus != 'dialing' && currentStatus != null) {
      debugPrint('[BG-LOG] Call $channelId is $currentStatus. Dismissing.');
      await FlutterCallkitIncoming.endAllCalls();
      return;
    }
  } catch (e) {
    debugPrint('[BG-LOG] Firestore status check failed: $e');
    return;
  }

  // 2. FRESHNESS CHECK: Ignore FCM messages older than 60 seconds
  final sentTime = message.sentTime;
  if (sentTime != null) {
    final now = DateTime.now();
    final difference = now.difference(sentTime).inSeconds;
    if (difference > 60) {
      debugPrint('[BG-LOG] Ignoring stale FCM message ($difference seconds old)');
      return;
    }
  }

  // 3. Handle End/Cancel signals explicitly
  if (status != 'dialing') {
    debugPrint('[BG-LOG] Received terminal signal ($status) for $channelId.');
    await FlutterCallkitIncoming.endAllCalls();
    return;
  }

  // 4. Show CallKit notification ONLY if no other call is active
  final activeCalls = await FlutterCallkitIncoming.activeCalls();
  if (activeCalls is List && activeCalls.isNotEmpty) {
    debugPrint('[BG-LOG] Another call is already active. Ignoring.');
    return;
  }

  final String callerName = data['cn'] ?? data['callerName'] ?? data['senderName'] ?? 'Unknown Caller';

  await CallKitService.showIncomingCall(
    callerName: callerName,
    callerId: data['uid'] ?? data['callerId'] ?? '',
    channelId: channelId,
    isAudioCall: data['ac'].toString() == 'true',
  );

  // 5. PERSISTENT MONITOR: While the ringer is active, listen to Firestore 
  final completer = Completer<void>();
  StreamSubscription? statusSub;
  
  statusSub = FirebaseFirestore.instance
      .collection('calls')
      .doc(channelId)
      .snapshots()
      .listen((snapshot) async {
    if (!snapshot.exists) {
      await FlutterCallkitIncoming.endAllCalls();
      statusSub?.cancel();
      if (!completer.isCompleted) completer.complete();
      return;
    }

    final currentStatus = snapshot.data()?['status'];
    if (currentStatus != 'dialing' && currentStatus != null) {
      await FlutterCallkitIncoming.endAllCalls();
      statusSub?.cancel();
      if (!completer.isCompleted) completer.complete();
    }
  });

  // BACKGROUND SIGNALING
  final sub = FlutterCallkitIncoming.onEvent.listen((event) async {
    if (event == null) return;
    if (event.event == Event.actionCallAccept || 
        event.event == Event.actionCallDecline || 
        event.event == Event.actionCallTimeout) {
      statusSub?.cancel();
      if (!completer.isCompleted) completer.complete();
    }
    
    final bgContainer = ProviderContainer();
    final body = Map<String, dynamic>.from(event.body as Map);
    final extra = body['extra'] != null ? Map<String, dynamic>.from(body['extra'] as Map) : null;
    final eventChannelId = extra?['channelId'] ?? body['id'];

    if (eventChannelId == channelId) {
      if (event.event == Event.actionCallDecline) {
        await bgContainer.read(callRepositoryProvider).updateCallStatus(channelId, 'declined');
      } else if (event.event == Event.actionCallTimeout) {
        await bgContainer.read(callRepositoryProvider).updateCallStatus(channelId, 'timed_out');
      } else if (event.event == Event.actionCallAccept) {
        FirebaseFirestore.instance.collection('calls').doc(channelId).set({
          'status': 'ongoing',
          'ongoingAt': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
  });

  Future.delayed(const Duration(seconds: 70), () {
    statusSub?.cancel();
    sub.cancel();
    if (!completer.isCompleted) completer.complete();
  });

  await completer.future;
  sub.cancel();
}

class TopNotificationService {
  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.greenAccent.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
