import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:call_project/features/call/presentation/screens/call_screen.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/notifications/presentation/services/callkit_service.dart';
import 'package:call_project/core/navigation/navigation_service.dart';
import 'package:call_project/features/call/data/repositories/call_repository.dart';
import 'package:call_project/features/call/presentation/controllers/call_controller.dart';
import 'package:call_project/features/auth/repository/auth_repository.dart';

class CallListener extends ConsumerStatefulWidget {
  final Widget child;
  const CallListener({super.key, required this.child});

  @override
  ConsumerState<CallListener> createState() => _CallListenerState();
}

class _CallListenerState extends ConsumerState<CallListener> {
  StreamSubscription? _fcmSubscription;
  static final Map<String, int> _handledCalls = {};

  final DateTime _appStartTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _setupFCM();
    _updateLastSeen();
  }

  void _updateLastSeen() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
        'isOnline': true,
      });
    }
  }

  @override
  void dispose() {
    _fcmSubscription?.cancel();
    super.dispose();
  }

  bool _shouldHandle(String channelId, int createdAt) {
    if (_handledCalls.containsKey(channelId) &&
        _handledCalls[channelId] == createdAt) {
      return false;
    }
    return true;
  }

  Future<void> _handleCallAccept(
    Map<String, dynamic> data,
    Map<String, dynamic>? extra,
  ) async {
    final channelId = extra?['channelId'] ?? data['id'] ?? '';
    if (channelId.isEmpty) return;

    // Check if we are already showing THIS call screen
    if (globalActiveCallId == channelId) {
      debugPrint('Already in call $channelId. Skipping navigation.');
      return;
    }

    // Mark as handled for background streams
    final createdAt = int.tryParse(extra?['createdAt']?.toString() ?? '') ?? 0;
    _handledCalls[channelId] = createdAt;

    globalActiveCallId = channelId;
    if (!mounted) return;

    // Ensure the Navigator is ready by waiting for the first frame + small delay
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Small extra delay for deep-linking/killed-state stability
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/call_screen'),
          builder: (_) => CallScreen(
            channelId: channelId,
            guestUser: UserModel(
              uid: extra?['callerId'] ?? '',
              email: '',
              displayName: data['nameCaller'] ?? 'Unknown',
            ),
            isAudioCall: data['type'].toString() == '0',
            isOutgoing: false,
          ),
        ),
      );

      // When returning from the call screen, clear the active call ID
      setState(() => globalActiveCallId = null);
    });
  }

  void _setupFCM() {
    // Listen for FCM messages in the foreground
    _fcmSubscription = FirebaseMessaging.onMessage.listen((
      RemoteMessage message,
    ) async {
      debugPrint('FCM message received in foreground: ${message.data}');
      final data = message.data;
      final type = data['t'] ?? data['type'];
      final status = data['s'] ?? data['status'] ?? 'dialing';
      final channelId = data['cid'] ?? data['channelId'] ?? '';
      
      if (type == 'call' || status == 'dialing') {
        if (channelId.isEmpty) return;

        // 1. FRESHNESS CHECK
        final createdAt = int.tryParse(message.data['createdAt']?.toString() ?? '') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (createdAt > 0 && (now - createdAt > 60000)) return;

        // 2. STATUS CHECK (Server side)
        try {
          final callDoc = await FirebaseFirestore.instance
              .collection('calls')
              .doc(channelId)
              .get(const GetOptions(source: Source.server));
          
          if (!callDoc.exists) {
            debugPrint('[FCM-LOG] Call doc $channelId missing. Ignoring.');
            return;
          }

          final status = callDoc.data()?['status'];
          if (status != 'dialing') {
            debugPrint('[FCM-LOG] Call $channelId is $status. Ignoring foreground signal.');
            return;
          }
        } catch (e) {
          debugPrint('Firestore check failed: $e');
          return; // Safer to skip
        }

        // ESCAPE: If we are already IN this call
        if (globalActiveCallId == channelId) return;
        if (!_shouldHandle(channelId, createdAt)) return;

        final callerName =
            data['cn'] ??
            data['callerName'] ??
            'Unknown';

        // Only show if no other call is active
        final activeCalls = await FlutterCallkitIncoming.activeCalls();
        if (activeCalls is List && activeCalls.isEmpty) {
          CallKitService.showIncomingCall(
            callerName: callerName,
            callerId: data['uid'] ?? data['callerId'] ?? '',
            channelId: channelId,
            isAudioCall: data['ac'].toString() == 'true',
          );
        }
      } else if (status != 'dialing') {
        await FlutterCallkitIncoming.endAllCalls();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return widget.child;

    // Listen for incoming calls in Firestore (Fallback/Sync)
    ref.listen<
      AsyncValue<QuerySnapshot>
    >(incomingCallStreamProvider(user.uid), (previous, next) {
      next.when(
        data: (snapshot) async {
          for (var doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final String channelId = data['channelId'] ?? doc.id;
            final String status = data['status'] ?? 'dialing';

            final rawTime = data['createdAt'];
            int createdAt = (rawTime is Timestamp)
                ? rawTime.millisecondsSinceEpoch
                : (rawTime is int ? rawTime : 0);

            final int now = DateTime.now().millisecondsSinceEpoch;

            // 1. FRESHNESS: Ignore calls older than 60 seconds
            if (createdAt > 0 && (now - createdAt > 60000)) continue;

            // 2. DISMISSAL: If this call is no longer dialing, dismiss CallKit
            if (status != 'dialing') {
              if (_handledCalls.containsKey(channelId)) {
                debugPrint('[STREAM-LOG] Call $channelId status changed to $status. Dismissing.');
                await FlutterCallkitIncoming.endAllCalls();
                
                // Remove from handled calls after a delay to prevent immediate re-trigger
                Future.delayed(const Duration(seconds: 30), () {
                  _handledCalls.remove(channelId);
                });
              }
              continue;
            }

            // 3. DIALING: New incoming call
            if (status == 'dialing') {
              if (data['senderId'] == user.uid || globalActiveCallId == channelId) {
                continue;
              }

              if (_handledCalls.containsKey(channelId)) continue;

              debugPrint('[STREAM-LOG] New dialing call detected: $channelId');
              _handledCalls[channelId] = createdAt;

              final activeCalls = await FlutterCallkitIncoming.activeCalls();
              if (activeCalls is List && activeCalls.isEmpty) {
                CallKitService.showIncomingCall(
                  callerName: data['callerName'] ?? data['senderName'] ?? 'Unknown',
                  callerId: data['callerId'] ?? data['senderId'] ?? '',
                  channelId: channelId,
                  isAudioCall: data['isAudioCall'] == true,
                );
              }
            }
          }
        },
        loading: () {},
        error: (e, st) => debugPrint('Error in call stream: $e'),
      );
    });

    return widget.child;
  }
}
