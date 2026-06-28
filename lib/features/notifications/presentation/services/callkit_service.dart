import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class CallKitService {
  static final Set<String> _shownChannels = {};

  static Future<void> showIncomingCall({
    required String callerName,
    required String callerId,
    required String channelId,
    bool isAudioCall = false,
  }) async {
    // 1. De-duplicate: Don't show the same channel twice
    if (_shownChannels.contains(channelId)) {
      return;
    }
    _shownChannels.add(channelId);

    // Clean up old channels after 5 minutes
    Future.delayed(
      const Duration(minutes: 5),
      () => _shownChannels.remove(channelId),
    );

    final params = CallKitParams(
      id: channelId, // Use channelId for internal plugin de-duplication
      nameCaller: callerName,
      appName: 'Agora Calling',
      avatar: 'https://i.pravatar.cc/100',
      handle: isAudioCall ? 'Audio Call' : 'Video Call',
      type: isAudioCall ? 0 : 1, // 0: Audio, 1: Video
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: {'channelId': channelId, 'callerId': callerId},
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        backgroundUrl: 'https://i.pravatar.cc/500',
        actionColor: '#4CAF50',
        isShowFullLockedScreen: true,
        incomingCallNotificationChannelName: 'Incoming Call',
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }
}
