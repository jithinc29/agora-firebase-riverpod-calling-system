import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:call_project/core/config/agora_config.dart';
import 'package:call_project/features/call/domain/entities/call_entity.dart';
import 'package:call_project/features/call/data/repositories/call_repository.dart';

part 'call_controller.g.dart';

@Riverpod(keepAlive: true)
class CallController extends _$CallController {
  RtcEngine? _engine;

  @override
  void build() {
    ref.onDispose(() {
      debugPrint('CallController disposed - releasing engine');
      _engine?.release();
    });
  }

  Future<void> initEngine({bool isAudioCall = false}) async {
    await [Permission.microphone, Permission.camera].request();

    if (_engine == null) {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        const RtcEngineContext(
          appId: AgoraConfig.appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
    }

    if (isAudioCall) {
      await _engine!.disableVideo();
    } else {
      await _engine!.enableVideo();
      await _engine!.startPreview();
    }

    // Default to speakerphone for video, earpiece for audio (can be toggled)
    try {
      await _engine!.setEnableSpeakerphone(!isAudioCall);
    } catch (e) {
      debugPrint('Error setting speakerphone in init: $e');
    }
  }

  Future<void> joinChannel(String channelId, String token) async {
    if (_engine == null) await initEngine();

    // Ensure we are not already in a channel to avoid error -17
    try {
      await _engine!.leaveChannel();
    } catch (e) {
      debugPrint('Error leaving channel before join: $e');
    }

    await _engine!.joinChannel(
      token: token,
      channelId: channelId,
      uid: 0,
      options: const ChannelMediaOptions(
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
      ),
    );
  }

  Future<String?> makeCall({
    required String senderId,
    required String senderName,
    required String receiverId,
    required String? receiverName,
    required String receiverToken,
    bool isAudioCall = false,
    String? channelId,
    BuildContext? context,
  }) async {
    // Shorten channelId to stay under Agora's 64-char limit (UIDs are 28 chars each)
    final shortSenderId = senderId.substring(0, 10);
    final shortReceiverId = receiverId.substring(0, 10);
    final generatedChannelId =
        channelId ??
        "${shortSenderId}_${shortReceiverId}_${DateTime.now().millisecondsSinceEpoch}";

    final call = CallEntity(
      callerId: senderId,
      callerName: senderName,
      receiverId: receiverId,
      receiverName: receiverName ?? 'Unknown',
      channelId: generatedChannelId,
      isAudioCall: isAudioCall,
    );

    try {
      // 1. SIGNAL FIRST: Write to Firestore (and Vercel/FCM)
      // CallRepository.makeCall handles BOTH Firestore and Vercel signaling.
      debugPrint('Step 1: Signaling Firestore & Vercel...');
      await ref.read(callRepositoryProvider).makeCall(call);

      // 2. Return the channelId IMMEDIATELY so the UI can navigate
      return generatedChannelId;
    } catch (e) {
      debugPrint('Error in makeCall process: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      return null;
    }
  }

  Future<void> acceptCall(String channelId, bool isAudioCall) async {
    try {
      // 1. Update status to ongoing with a timestamp for timer sync
      await ref
          .read(callRepositoryProvider)
          .updateCallStatus(channelId, 'ongoing');
      await ref.read(callRepositoryProvider).updateCallData(channelId, {
        'ongoingAt': DateTime.now().millisecondsSinceEpoch,
      });

      // 2. The navigation and Agora join is handled by the CallScreen,
      // but we could also centralize it here if needed.
    } catch (e) {
      debugPrint('Error in acceptCall: $e');
    }
  }

  Future<void> endCall(String channelId, {String status = 'ended'}) async {
    // CRITICAL: Leave and release Agora FIRST so background connections are severed instantly
    if (_engine != null) {
      try {
        await _engine!.leaveChannel();
        await _engine!.release();
      } catch (e) {
        debugPrint('Error during endCall cleanup: $e');
      }
      _engine = null;
    }

    // Then update Firestore and CallKit
    await ref.read(callRepositoryProvider).updateCallStatus(channelId, status);
    await FlutterCallkitIncoming.endAllCalls();
  }

  Future<void> toggleMute(bool isMuted) async {
    await _engine?.muteLocalAudioStream(isMuted);
  }

  Future<void> toggleVideo(bool isVideoEnabled) async {
    await _engine?.muteLocalVideoStream(!isVideoEnabled);
  }

  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }

  Future<void> toggleSpeakerphone(bool isSpeakerOn) async {
    await _engine?.setEnableSpeakerphone(isSpeakerOn);
  }

  RtcEngine? get engine => _engine;
}
