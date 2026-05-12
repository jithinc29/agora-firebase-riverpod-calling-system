import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/call/data/repositories/call_repository.dart';
import 'package:call_project/features/call/presentation/controllers/call_state_controller.dart';
import 'package:call_project/features/call/presentation/screens/call_screen.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';

class CallEventService {
  final ProviderContainer container;
  final GlobalKey<NavigatorState> navigatorKey;

  CallEventService(this.container, this.navigatorKey);

  Future<void> handleEvent(dynamic event) async {
    final body = Map<String, dynamic>.from(event.body as Map);
    final extra = body['extra'] != null ? Map<String, dynamic>.from(body['extra'] as Map) : null;
    final channelId = extra?['channelId'] ?? body['id'] ?? '';
    if (channelId.isEmpty) return;

    final callState = container.read(callStateControllerProvider.notifier);
    final repository = container.read(callRepositoryProvider);

    switch (event.event) {
      case Event.actionCallAccept:
        debugPrint('[EVENT-SERVICE] Accept captured: $channelId');
        callState.setActiveCall(channelId);
        
        final guestUser = UserModel(
          uid: extra?['callerId'] ?? '',
          email: '',
          displayName: body['nameCaller'] ?? 'Unknown',
          isOnline: true,
        );
        
        // Wait for navigator
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
          ).then((_) => callState.clearActiveCall());
        }
        break;
        
      case Event.actionCallDecline:
        debugPrint('[EVENT-SERVICE] Decline captured: $channelId');
        callState.clearActiveCall();
        
        await _ensureAuth();
        if (FirebaseAuth.instance.currentUser != null) {
          await repository.updateCallStatus(channelId, 'declined');
        }
        break;

      case Event.actionCallTimeout:
        debugPrint('[EVENT-SERVICE] Timeout captured: $channelId');
        callState.clearActiveCall();
        
        await _ensureAuth();
        if (FirebaseAuth.instance.currentUser != null) {
          await repository.updateCallStatus(channelId, 'timed_out');
        }
        break;

      case Event.actionCallEnded:
        debugPrint('[EVENT-SERVICE] Ended captured: $channelId');
        callState.clearActiveCall();
        break;
        
      default:
        break;
    }
  }

  Future<void> _ensureAuth() async {
    for (int i = 0; i < 20; i++) {
      if (FirebaseAuth.instance.currentUser != null) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }
}
