import 'dart:async';
import 'dart:ui';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:call_project/features/call/presentation/controllers/call_controller.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/call/data/repositories/call_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio/just_audio.dart';

// Unified Design System Colors (Synced across app)
class AppColors {
  static const primary = Color(0xFF6366F1); // Indigo
  static const secondary = Color(0xFFA855F7); // Purple
  static const background = Color(0xFFF8FAFC); // Slate Light
  static const darkSurface = Color(0xFF0F172A); // Midnight
  static const success = Color(0xFF10B981); // Emerald
  static const error = Color(0xFFEF4444); // Rose
  static const textPrimary = Color(0xFF1E293B);
  static const textSecondary = Color(0xFF64748B);
}

class CallScreen extends ConsumerStatefulWidget {
  final String channelId;
  final UserModel guestUser;
  final bool isAudioCall;
  final bool isOutgoing;

  const CallScreen({
    super.key,
    required this.channelId,
    required this.guestUser,
    this.isAudioCall = false,
    this.isOutgoing = true,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> with SingleTickerProviderStateMixin {
  int? _remoteUid;
  bool _localUserJoined = false;
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerOn = true;
  Timer? _timer;
  Duration _duration = Duration.zero;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isDisposed = false;
  final int _startTime = DateTime.now().millisecondsSinceEpoch;
  late final CallController _controller;
  late AnimationController _pulseController;
  ProviderSubscription? _callStreamSubscription;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(callControllerProvider.notifier);
    _isSpeakerOn = !widget.isAudioCall;
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    if (widget.isOutgoing) {
      _playOutgoingRingtone();
      _startTimeoutTimer();
    }
    _initAgora();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _stopRingtone();
    _pulseController.dispose();
    _callStreamSubscription?.close();
    _controller.endCall(widget.channelId);
    _audioPlayer.dispose();
    super.dispose();
  }

  void _startTimer() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _duration = Duration(seconds: _duration.inSeconds + 1);
        });
      }
    });
  }

  Future<void> _playOutgoingRingtone() async {
    if (_isDisposed) return;
    try {
      await _audioPlayer.setLoopMode(LoopMode.one);
      await _audioPlayer.setAsset('assets/sounds/ringtone.wav');
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('Error playing ringtone: $e');
    }
  }

  Future<void> _stopRingtone() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint('Error stopping ringtone: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  String? _statusMessage;

  Future<void> _checkConnectionStatus() async {
    if (_timer != null || _isDisposed) return;
    try {
      final snapshot = await ref.read(callRepositoryProvider).callStream(widget.channelId).first;
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        if (data['status'] == 'ongoing') {
          _stopRingtone();
          final int? ongoingAt = data['ongoingAt'];
          if (ongoingAt != null) {
            final now = DateTime.now().millisecondsSinceEpoch;
            _duration = Duration(seconds: (now - ongoingAt) ~/ 1000);
          }
          if (_remoteUid != null) _startTimer();
          if (mounted) setState(() {}); 
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _startTimeoutTimer() {
    Timer(const Duration(seconds: 45), () {
      if (mounted && _remoteUid == null && !_isDisposed) {
        setState(() => _statusMessage = "NO RESPONSE");
        _stopRingtone();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _controller.endCall(widget.channelId, status: 'timed_out');
            Navigator.of(context).pop();
          }
        });
      }
    });
  }

  Future<void> _initAgora() async {
    await _controller.initEngine(isAudioCall: widget.isAudioCall);
    _controller.engine?.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          if (mounted) setState(() => _localUserJoined = true);
          if (!widget.isOutgoing) {
            ref.read(callRepositoryProvider).updateCallStatus(widget.channelId, 'ongoing');
          }
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          setState(() => _remoteUid = remoteUid);
          _checkConnectionStatus();
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          setState(() => _remoteUid = null);
          _timer?.cancel();
          _stopRingtone();
          _controller.endCall(widget.channelId);
          if (mounted) Navigator.of(context).pop();
        },
      ),
    );

    final token = await ref.read(callRepositoryProvider).getAgoraToken(widget.channelId, 0);
    if (token == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    await _controller.joinChannel(widget.channelId, token);

    _callStreamSubscription = ref.listenManual<AsyncValue<DocumentSnapshot>>(callStreamProvider(widget.channelId), (previous, next) {
      final snapshot = next.asData?.value;
      if (snapshot != null && snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final rawCreatedAt = data['createdAt'];
        int createdAt = rawCreatedAt is Timestamp ? rawCreatedAt.millisecondsSinceEpoch : (rawCreatedAt ?? 0);
        if (createdAt > _startTime - 10000 && (data['status'] == 'ended' || data['status'] == 'timed_out' || data['status'] == 'declined')) {
          _stopRingtone();
          final status = data['status'];
          if (mounted) {
            setState(() => _statusMessage = status == 'declined' ? "DECLINED" : "DISCONNECTED");
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                Navigator.of(context).pop();
              }
            });
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkSurface,
      body: Stack(
        children: [
          // Background (Video or Gradient)
          if (widget.isAudioCall) _buildAudioBackground() else _buildVideoBackground(),

          // Glassmorphic Overlay for Audio Call
          if (widget.isAudioCall) BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.black.withValues(alpha: 0.2))),

          // UI Layer
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),
                _buildTopInfo(),
                const Spacer(),
                if (widget.isAudioCall || _remoteUid == null) _buildMainProfile(),
                const Spacer(),
                _buildBottomToolbar(),
                const SizedBox(height: 40),
              ],
            ),
          ),

          // Small PIP for Video Call
          if (!widget.isAudioCall && _localUserJoined) _buildLocalVideoPIP(),
        ],
      ),
    );
  }

  Widget _buildTopInfo() {
    return Column(
      children: [
        StreamBuilder<DocumentSnapshot>(
          stream: ref.watch(callRepositoryProvider).callStream(widget.channelId),
          builder: (context, snapshot) {
            String status = "CONNECTING...";
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              status = data['status'] == 'ongoing' ? "CONNECTED" : "CALLING...";
            }
            if (_statusMessage != null) status = _statusMessage!;
            
            return Text(
              status,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2),
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          _formatDuration(_duration),
          style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w300, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  Widget _buildMainProfile() {
    return Column(
      children: [
        FadeTransition(
          opacity: _pulseController,
          child: ScaleTransition(
            scale: Tween(begin: 1.0, end: 1.05).animate(_pulseController),
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 8),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 40, spreadRadius: 10),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(80),
                child: widget.guestUser.photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: widget.guestUser.photoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        ),
                        errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
                      )
                    : Container(
                        color: AppColors.primary,
                        child: Center(
                          child: Text(
                            widget.guestUser.displayName[0].toUpperCase(),
                            style: const TextStyle(fontSize: 64, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          widget.guestUser.displayName,
          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          widget.isAudioCall ? 'Audio Call' : 'Video Call',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildBottomToolbar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            isActive: _isMuted,
            color: _isMuted ? AppColors.error : Colors.white,
            onTap: () {
              setState(() => _isMuted = !_isMuted);
              _controller.toggleMute(_isMuted);
            },
          ),
          if (!widget.isAudioCall)
            _buildControlButton(
              icon: _isVideoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              isActive: !_isVideoEnabled,
              color: !_isVideoEnabled ? AppColors.error : Colors.white,
              onTap: () {
                setState(() => _isVideoEnabled = !_isVideoEnabled);
                _controller.toggleVideo(_isVideoEnabled);
              },
            ),
          _buildControlButton(
            icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
            isActive: _isSpeakerOn,
            color: _isSpeakerOn ? AppColors.success : Colors.white,
            onTap: () {
              setState(() => _isSpeakerOn = !_isSpeakerOn);
              _controller.toggleSpeakerphone(_isSpeakerOn);
            },
          ),
          _buildControlButton(
            icon: Icons.call_end_rounded,
            color: Colors.white,
            backgroundColor: AppColors.error,
            isLarge: true,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({required IconData icon, Color color = Colors.white, Color? backgroundColor, bool isActive = false, bool isLarge = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isLarge ? 64 : 52,
        height: isLarge ? 64 : 52,
        decoration: BoxDecoration(
          color: backgroundColor ?? (isActive ? Colors.white.withValues(alpha: 0.2) : Colors.transparent),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: isLarge ? 32 : 24),
      ),
    );
  }

  Widget _buildAudioBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.darkSurface, Color(0xFF1E1B4B)],
        ),
      ),
    );
  }

  Widget _buildVideoBackground() {
    if (_remoteUid != null && _controller.engine != null) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _controller.engine!,
          canvas: VideoCanvas(uid: _remoteUid),
          connection: RtcConnection(channelId: widget.channelId),
        ),
      );
    }
    return _buildAudioBackground();
  }

  Widget _buildLocalVideoPIP() {
    return Positioned(
      right: 20,
      top: 60,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 100,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: AgoraVideoView(
            controller: VideoViewController(
              rtcEngine: _controller.engine!,
              canvas: const VideoCanvas(uid: 0),
            ),
          ),
        ),
      ),
    );
  }
}
