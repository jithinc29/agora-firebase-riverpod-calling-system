import 'package:call_project/core/providers/refresh_provider.dart';
import 'package:call_project/features/profile/presentation/screens/profile_screen.dart'
    hide AppColors;
import 'package:call_project/features/users/data/repository/user_repository.dart';
import 'package:call_project/features/users/presentation/screens/user_profile_screen.dart'
    hide AppColors;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/home/presentation/screens/home_screen.dart'
    show AppColors, feedMuteProvider;
import 'package:call_project/core/services/notification_service.dart';

class ReelsPlayerItem extends ConsumerStatefulWidget {
  final DocumentSnapshot? reelDoc;
  final UserModel? currentUser;
  final String videoUrl;
  final String? thumbnailUrl;
  final String caption;
  final String creatorName;
  final String? creatorAvatar;
  final bool isActive;
  final VideoPlayerController? controller;
  final VoidCallback? onCommentTap;

  const ReelsPlayerItem({
    super.key,
    this.reelDoc,
    this.currentUser,
    required this.videoUrl,
    this.thumbnailUrl,
    required this.caption,
    required this.creatorName,
    this.creatorAvatar,
    required this.isActive,
    this.controller,
    this.onCommentTap,
  });

  @override
  ConsumerState<ReelsPlayerItem> createState() => _ReelsPlayerItemState();
}

class _ReelsPlayerItemState extends ConsumerState<ReelsPlayerItem> {
  bool _isMuted = false;
  bool _showPlayPauseOverlay = false;
  VideoPlayerController? _currentController;

  @override
  void initState() {
    super.initState();
    _currentController = widget.controller;
    _currentController?.addListener(_onControllerUpdated);
  }

  void _onControllerUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant ReelsPlayerItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update the listener when the controller object itself changes
    if (widget.controller != _currentController) {
      _currentController?.removeListener(_onControllerUpdated);
      _currentController = widget.controller;
      _currentController?.addListener(_onControllerUpdated);
    }
    // NOTE: We deliberately do NOT call play/pause here.
    // The parent _HomeScreenState._manageReelsControllers() is the single
    // authority for play/pause decisions. Calling it here creates races
    // with the async init completing and causes audio-from-wrong-reel bugs.
  }

  @override
  void dispose() {
    _currentController?.removeListener(_onControllerUpdated);
    super.dispose();
  }

  void _togglePlayPause() {
    final controller = widget.controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
      _showPlayPauseOverlay = true;
    });

    // Auto hide overlay after 800ms
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showPlayPauseOverlay = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isInitialized =
        widget.controller != null && widget.controller!.value.isInitialized;

    return Container(
      width: size.width,
      height: size.height,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video Player scaled to cover the screen natively
          GestureDetector(
            onTap: _togglePlayPause,
            child: isInitialized
                ? RepaintBoundary(
                    child: SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: widget.controller!.value.size.width,
                          height: widget.controller!.value.size.height,
                          child: VideoPlayer(widget.controller!),
                        ),
                      ),
                    ),
                  )
                : (widget.thumbnailUrl != null &&
                      widget.thumbnailUrl!.isNotEmpty)
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: widget.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: Colors.black),
                        errorWidget: (context, url, error) =>
                            Container(color: Colors.black),
                      ),
                      Shimmer.fromColors(
                        baseColor: Colors.transparent,
                        highlightColor: Colors.white.withOpacity(0.3),
                        child: Container(color: Colors.black.withOpacity(0.4)),
                      ),
                    ],
                  )
                : Container(color: Colors.black),
          ),

          // Play/Pause Tap Overlay Indicator
          if (_showPlayPauseOverlay && widget.controller != null)
            Center(
              child: RepaintBoundary(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _showPlayPauseOverlay ? 1.0 : 0.0,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.controller!.value.isPlaying
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),

          // Right Side Action Buttons & Bottom Info overlay
          Positioned(
            left: 16,
            bottom: 72, // above bottom nav
            right: 80,
            child: widget.reelDoc != null
                ? StreamBuilder<DocumentSnapshot>(
                    stream: widget.reelDoc!.reference.snapshots(),
                    builder: (context, snapshot) {
                      final doc = snapshot.data ?? widget.reelDoc!;
                      final data = doc.data() as Map<String, dynamic>? ?? {};

                      final creatorAvatar =
                          data['photoUrl'] as String? ?? widget.creatorAvatar;
                      final creatorName =
                          data['displayName'] as String? ?? widget.creatorName;
                      final uid = data['uid'] as String?;

                      // Fallback: If reel has no uid (old reel), check if creatorName matches current user
                      final isMe =
                          widget.currentUser != null &&
                          ((uid != null && uid == widget.currentUser!.uid) ||
                              (uid == null &&
                                  creatorName ==
                                      widget.currentUser!.displayName) ||
                              (uid == null &&
                                  creatorName ==
                                      '@${widget.currentUser!.displayName}'));

                      final isFollowing =
                          uid != null &&
                          widget.currentUser != null &&
                          widget.currentUser!.following.contains(uid);

                      return _buildAuthorInfo(
                        creatorAvatar,
                        creatorName,
                        widget.caption,
                        isMe,
                        isFollowing,
                        uid,
                      );
                    },
                  )
                : _buildAuthorInfo(
                    widget.creatorAvatar,
                    widget.creatorName,
                    widget.caption,
                    false,
                    false,
                    null,
                  ),
          ),

          // Right Sidebar Actions
          Positioned(
            right: 16,
            bottom: 72,
            child: widget.reelDoc != null && widget.currentUser != null
                ? StreamBuilder<DocumentSnapshot>(
                    stream: widget.reelDoc!.reference.snapshots(),
                    builder: (context, snapshot) {
                      final doc = snapshot.data ?? widget.reelDoc!;
                      final data = doc.data() as Map<String, dynamic>? ?? {};
                      final likes = List<String>.from(data['likes'] ?? []);
                      final isLiked = likes.contains(widget.currentUser!.uid);
                      final likeCount = likes.length;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildReelAction(
                            icon: isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            label: _formatCount(likeCount),
                            color: isLiked ? Colors.red : Colors.white,
                            onTap: () {
                              final updatedLikes = List<String>.from(likes);
                              if (isLiked) {
                                updatedLikes.remove(widget.currentUser!.uid);
                              } else {
                                updatedLikes.add(widget.currentUser!.uid);
                              }
                              doc.reference.update({'likes': updatedLikes});
                            },
                          ),
                          const SizedBox(height: 16),
                          StreamBuilder<QuerySnapshot>(
                            stream: doc.reference
                                .collection('comments')
                                .snapshots(),
                            builder: (context, commentSnapshot) {
                              final commentCount = commentSnapshot.hasData
                                  ? commentSnapshot.data!.docs.length
                                  : 0;
                              return _buildReelAction(
                                icon: Icons.mode_comment_rounded,
                                label: _formatCount(commentCount),
                                onTap: widget.onCommentTap ?? () {},
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildReelAction(
                            icon: Icons.share_rounded,
                            label: 'Share',
                            onTap: () {
                              final link =
                                  'https://callingapp.page.link/reel/${doc.id}';
                              Clipboard.setData(ClipboardData(text: link));
                              TopNotificationService.showSuccess(
                                context,
                                'Reel link copied to clipboard!',
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          if (data['uid'] == widget.currentUser?.uid) ...[
                            _buildReelAction(
                              icon: data['isHidden'] == true
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              label: data['isHidden'] == true
                                  ? 'Unhide'
                                  : 'Archive',
                              color: Colors.white,
                              onTap: () async {
                                final bool isHidden = data['isHidden'] == true;
                                await doc.reference.update({
                                  'isHidden': !isHidden,
                                });
                                ref.read(mediaRefreshProvider.notifier).state++;
                                if (context.mounted) {
                                  TopNotificationService.showSuccess(
                                    context,
                                    isHidden
                                        ? 'Reel unhidden'
                                        : 'Reel archived',
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildReelAction(
                              icon: Icons.delete_rounded,
                              label: 'Delete',
                              color: AppColors.error,
                              onTap: () {
                                _confirmDeleteReel(context, doc);
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                          _buildMuteAction(),
                        ],
                      );
                    },
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildReelAction(
                        icon: Icons.favorite_border_rounded,
                        label: '0',
                        onTap: () {},
                      ),
                      const SizedBox(height: 16),
                      _buildReelAction(
                        icon: Icons.mode_comment_rounded,
                        label: '0',
                        onTap: () {},
                      ),
                      const SizedBox(height: 16),
                      _buildReelAction(
                        icon: Icons.share_rounded,
                        label: 'Share',
                        onTap: () {},
                      ),
                      const SizedBox(height: 16),
                      _buildMuteAction(),
                    ],
                  ),
          ),

          // Thin scrubbing timeline seekbar above bottom navigation
          if (isInitialized)
            Positioned(
              left: 0,
              right: 0,
              bottom: 64,
              child: RepaintBoundary(
                child: VideoProgressIndicator(
                  widget.controller!,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white70,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAuthorInfo(
    String? avatarUrl,
    String name,
    String caption,
    bool isMe,
    bool isFollowing,
    String? uid,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            if (uid == null) return;
            widget.controller?.pause();
            if (isMe) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
              return;
            }
            final users = ref.read(allUsersProvider).value;
            if (users == null) return;
            try {
              final user = users.firstWhere((u) => u.uid == uid);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(user: user),
                ),
              );
            } catch (e) {
              debugPrint('User not found for uid: $uid');
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white30,
                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? NetworkImage(avatarUrl)
                    : null,
                child: (avatarUrl == null || avatarUrl.isEmpty)
                    ? const Icon(Icons.person, color: Colors.white, size: 20)
                    : null,
              ),
              const SizedBox(width: 10),
              Text(
                name.startsWith('@') ? name : '@$name',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
              if (!isMe && !isFollowing) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Follow',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          caption,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            shadows: [Shadow(blurRadius: 4, color: Colors.black)],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildReelAction({
    required IconData icon,
    required String label,
    Color color = Colors.white,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.black38,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(blurRadius: 4, color: Colors.black)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMuteAction() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isMuted = !_isMuted;
          widget.controller?.setVolume(_isMuted ? 0 : 1);
        });
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.black38,
          shape: BoxShape.circle,
        ),
        child: Icon(
          _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  void _confirmDeleteReel(BuildContext context, DocumentSnapshot reelDoc) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Delete Reel',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Are you sure you want to delete this reel permanently? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final data = reelDoc.data() as Map<String, dynamic>? ?? {};
                final videoUrl = data['videoUrl'] as String?;
                if (videoUrl != null && videoUrl.isNotEmpty) {
                  try {
                    final storageRef = FirebaseStorage.instance.refFromURL(
                      videoUrl,
                    );
                    await storageRef.delete();
                  } catch (e) {
                    debugPrint('Failed to delete reel media: $e');
                  }
                }
                final thumbnailUrl = data['thumbnail'] as String?;
                if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
                  try {
                    final storageRef = FirebaseStorage.instance.refFromURL(
                      thumbnailUrl,
                    );
                    await storageRef.delete();
                  } catch (e) {
                    debugPrint('Failed to delete reel thumbnail: $e');
                  }
                }
                await reelDoc.reference.delete();
                ref.read(mediaRefreshProvider.notifier).state++;
                TopNotificationService.showSuccess(context, 'Reel deleted');
              } catch (e) {
                TopNotificationService.showError(
                  context,
                  'Failed to delete reel: $e',
                );
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Instagram Story Viewer Overlay Dialog
// ----------------------------------------------------------------------
