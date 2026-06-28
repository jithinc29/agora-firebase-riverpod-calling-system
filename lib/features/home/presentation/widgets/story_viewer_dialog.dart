import 'package:call_project/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:call_project/core/utils/time_utils.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/core/services/notification_service.dart';
import 'package:call_project/core/widgets/custom_avatar.dart';

class StoryViewerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> stories;

  const StoryViewerDialog({super.key, required this.stories});

  @override
  State<StoryViewerDialog> createState() => _StoryViewerDialogState();
}

class _StoryViewerDialogState extends State<StoryViewerDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  VideoPlayerController? _videoController;
  bool _isPlayerInitialized = false;
  bool _hasPlayerError = false;
  int _currentIndex = 0;
  bool _isHolding = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this);
    _loadStory(_currentIndex);
  }

  void _loadStory(int index) async {
    _progressController.stop();
    _progressController.reset();
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;

    if (mounted) {
      setState(() {
        _isPlayerInitialized = false;
        _hasPlayerError = false;
      });
    }

    final story = widget.stories[index];
    final String type = story['type'] ?? 'image';
    final String? mediaUrl = story['mediaUrl'];

    if (type == 'video' && mediaUrl != null) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(mediaUrl));
      _videoController!
          .initialize()
          .then((_) {
            if (mounted && _currentIndex == index) {
              setState(() {
                _isPlayerInitialized = true;
              });
              _videoController!.play();

              final duration = _videoController!.value.duration;
              _progressController.duration = duration.inSeconds > 0
                  ? duration
                  : const Duration(seconds: 6);

              _progressController.forward().then((_) {
                if (mounted && _currentIndex == index) {
                  _nextStory();
                }
              });
            }
          })
          .catchError((error) {
            debugPrint("Story Video Player Error: $error");
            if (mounted && _currentIndex == index) {
              setState(() {
                _hasPlayerError = true;
              });
              _progressController.duration = const Duration(seconds: 5);
              _progressController.forward().then((_) {
                if (mounted && _currentIndex == index) {
                  _nextStory();
                }
              });
            }
          });
    } else if (type == 'image' && mediaUrl != null) {
      _progressController.duration = const Duration(seconds: 5);
      // For images, we start the timer in _buildBackground using imageBuilder
    } else {
      _progressController.duration = const Duration(seconds: 5);
      _progressController.forward().then((_) {
        if (mounted && _currentIndex == index) {
          _nextStory();
        }
      });
    }
  }

  void _nextStory() {
    if (_currentIndex < widget.stories.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _loadStory(_currentIndex);
    } else {
      _progressController.stop();
      _videoController?.pause();
      Navigator.of(context).pop();
    }
  }

  void _previousStory() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _loadStory(_currentIndex);
    } else {
      // Re-play first story from beginning
      _loadStory(0);
    }
  }

  @override
  void dispose() {
    _progressController.stop();
    _progressController.dispose();
    _videoController?.pause();
    _videoController?.dispose();
    super.dispose();
  }

  Widget _buildBackground(Map<String, dynamic> story) {
    final String type = story['type'] ?? 'image';
    final String? mediaUrl = story['mediaUrl'];

    // Gradient colors fallback
    final List<Color> colors = [
      const Color(0xFF6366F1),
      const Color(0xFFA855F7),
    ];

    if (type == 'image' && mediaUrl != null) {
      return Positioned.fill(
        child: RepaintBoundary(
          child: StoryImageItem(
            imageUrl: mediaUrl,
            onLoaded: () {
              if (mounted &&
                  !_progressController.isAnimating &&
                  !_progressController.isCompleted &&
                  !_isHolding &&
                  _currentIndex == widget.stories.indexOf(story)) {
                _progressController.forward().then((_) {
                  if (mounted &&
                      _currentIndex == widget.stories.indexOf(story)) {
                    _nextStory();
                  }
                });
              }
            },
            placeholder: const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
            errorWidget: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
        ),
      );
    } else if (type == 'video' && mediaUrl != null) {
      if (_isPlayerInitialized && _videoController != null) {
        return Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          ),
        );
      } else if (_hasPlayerError) {
        return Positioned.fill(
          child: Container(
            color: Colors.black,
            child: const Center(
              child: Text(
                'Failed to load video',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        );
      } else {
        return Positioned.fill(
          child: Container(
            color: Colors.black26,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        );
      }
    }

    // Default gradient for text stories
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stories.isEmpty) return const SizedBox.shrink();

    final story = widget.stories[_currentIndex];
    final isTextStory = story['type'] == 'text';
    final text = story['text'] ?? '';

    // Find the first story in the group with a non-empty photoUrl or displayName
    final firstWithPhoto = widget.stories.firstWhere(
      (s) => s['photoUrl'] != null && (s['photoUrl'] as String).isNotEmpty,
      orElse: () => widget.stories.first,
    );
    final firstWithDisplayName = widget.stories.firstWhere(
      (s) =>
          s['displayName'] != null && (s['displayName'] as String).isNotEmpty,
      orElse: () => widget.stories.first,
    );

    final String displayName = firstWithDisplayName['displayName'] ?? 'User';
    final String? photoUrl = firstWithPhoto['photoUrl'];

    final int timestamp = parseTimestamp(story['timestamp']);
    String timeAgo = '';
    if (timestamp > 0) {
      final diff = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
      if (diff.inMinutes < 1) {
        timeAgo = 'now';
      } else if (diff.inHours < 1) {
        timeAgo = '${diff.inMinutes}m';
      } else {
        timeAgo = '${diff.inHours}h';
      }
    }

    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          // Story Background
          _buildBackground(story),

          // Dark overlay for readability on image/video backgrounds
          if (!isTextStory)
            const Positioned.fill(
              child: RepaintBoundary(
                child: ColoredBox(color: Color(0x40000000)),
              ),
            ),

          // Content Layout (Text or Caption)
          if (!_isHolding && isTextStory)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    shadows: [
                      Shadow(
                        color: Colors.black45,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else if (!_isHolding && text.isNotEmpty)
            Positioned(
              bottom: 30,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // Interactive tap/longpress handler area
          Positioned.fill(
            child: GestureDetector(
              onTapUp: (details) {
                final width = MediaQuery.of(context).size.width;
                final dx = details.globalPosition.dx;
                if (dx < width * 0.3) {
                  _previousStory();
                } else {
                  _nextStory();
                }
              },
              onLongPress: () {
                setState(() {
                  _isHolding = true;
                });
                _progressController.stop();
                _videoController?.pause();
              },
              onLongPressEnd: (_) {
                setState(() {
                  _isHolding = false;
                });
                _videoController?.play();
                _progressController.forward().then((_) {
                  if (mounted) {
                    _nextStory();
                  }
                });
              },
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(),
            ),
          ),

          // Header Details
          if (!_isHolding)
            Positioned(
              top: 20,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  // Segmented Progress Indicator Bar
                  RepaintBoundary(
                    child: Row(
                      children: List.generate(widget.stories.length, (index) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2.0,
                            ),
                            child: AnimatedBuilder(
                              animation: _progressController,
                              builder: (context, child) {
                                double val = 0.0;
                                if (index < _currentIndex) {
                                  val = 1.0;
                                } else if (index == _currentIndex) {
                                  val = _progressController.value;
                                }
                                return CustomPaint(
                                  size: const Size(double.infinity, 3),
                                  painter: _SegmentBarPainter(value: val),
                                );
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Creator Info Row
                  RepaintBoundary(
                    child: Row(
                      children: [
                        CustomAvatar(
radius: 18,
photoUrl: photoUrl,
),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black45,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (timeAgo.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  timeAgo,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black45,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                            size: 24,
                          ),
                          onSelected: (value) async {
                            if (value == 'close') {
                              _progressController.stop();
                              _videoController?.pause();
                              Navigator.of(context).pop();
                            } else if (value == 'share') {
                              _progressController.stop();
                              _videoController?.pause();
                              try {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text:
                                        'https://callproject.app/story/${story['id']}',
                                  ),
                                );
                                if (mounted) {
                                  TopNotificationService.showSuccess(
                                    context,
                                    'Link copied to clipboard!',
                                  );
                                  _progressController.forward();
                                  _videoController?.play();
                                }
                              } catch (e) {
                                _progressController.forward();
                                _videoController?.play();
                              }
                            } else if (value == 'delete') {
                              _progressController.stop();
                              _videoController?.pause();
                              try {
                                final storyId = story['id'];
                                if (storyId != null) {
                                  await FirebaseFirestore.instance
                                      .collection('stories')
                                      .doc(storyId)
                                      .delete();
                                  if (mounted) {
                                    TopNotificationService.showSuccess(
                                      context,
                                      'Story deleted.',
                                    );
                                    Navigator.of(context).pop();
                                  }
                                }
                              } catch (e) {
                                if (mounted) {
                                  TopNotificationService.showError(
                                    context,
                                    'Failed to delete story.',
                                  );
                                  _progressController.forward();
                                  _videoController?.play();
                                }
                              }
                            }
                          },
                          onCanceled: () {
                            _progressController.forward();
                            _videoController?.play();
                          },
                          onOpened: () {
                            _progressController.stop();
                            _videoController?.pause();
                          },
                          itemBuilder: (context) {
                            final currentUid =
                                FirebaseAuth.instance.currentUser?.uid;
                            final isOwner =
                                currentUid != null &&
                                currentUid == story['uid'];
                            return [
                              if (isOwner)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    'Delete Story',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'share',
                                child: Text('Share Link'),
                              ),
                              const PopupMenuItem(
                                value: 'close',
                                child: Text('Close Viewer'),
                              ),
                            ];
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

final feedVideoVisibilityProvider = StateProvider<Map<String, double>>(
  (ref) => {},
);

class _SegmentBarPainter extends CustomPainter {
  final double value;
  _SegmentBarPainter({required this.value});

  static final Paint _bgPaint = Paint()..color = Colors.white24;
  static final Paint _fgPaint = Paint()..color = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(2),
    );
    canvas.drawRRect(rrect, _bgPaint);

    if (value > 0) {
      final fgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width * value, size.height),
        const Radius.circular(2),
      );
      canvas.drawRRect(fgRect, _fgPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentBarPainter oldDelegate) {
    return oldDelegate.value != value;
  }
}

class StoryImageItem extends StatefulWidget {
  final String imageUrl;
  final VoidCallback onLoaded;
  final Widget? placeholder;
  final Widget? errorWidget;

  const StoryImageItem({
    super.key,
    required this.imageUrl,
    required this.onLoaded,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<StoryImageItem> createState() => _StoryImageItemState();
}

class _StoryImageItemState extends State<StoryImageItem> {
  bool _timerStarted = false;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: widget.imageUrl,
      fit: BoxFit.cover,
      imageBuilder: (context, imageProvider) {
        if (!_timerStarted) {
          _timerStarted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onLoaded();
          });
        }
        return Image(image: imageProvider, fit: BoxFit.cover);
      },
      placeholder: widget.placeholder != null
          ? (context, url) => widget.placeholder!
          : null,
      errorWidget: widget.errorWidget != null
          ? (context, url, error) {
              if (!_timerStarted) {
                _timerStarted = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) widget.onLoaded();
                });
              }
              return widget.errorWidget!;
            }
          : null,
    );
  }
}

class StoryHeader extends StatelessWidget {
  final UserModel currentUser;
  final void Function(List<Map<String, dynamic>>) onStoryTap;
  final void Function() onAddStoryTap;

  const StoryHeader({
    super.key,
    required this.currentUser,
    required this.onStoryTap,
    required this.onAddStoryTap,
  });

  List<String> _buildSortedUids(
    Map<String, List<Map<String, dynamic>>> grouped,
    String myUid,
  ) {
    final uids = grouped.keys.where((uid) => uid != myUid).toList();
    uids.sort((a, b) {
      final tA = parseTimestamp(grouped[a]!.first['timestamp']);
      final tB = parseTimestamp(grouped[b]!.first['timestamp']);
      return tB.compareTo(tA);
    });
    return uids;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('stories')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final List<DocumentSnapshot> allDocs = snapshot.data?.docs ?? [];
        final now = DateTime.now().millisecondsSinceEpoch;
        final cutoff = now - (24 * 60 * 60 * 1000);

        final Map<String, List<Map<String, dynamic>>> grouped = {};
        for (var doc in allDocs) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final uid = data['uid'] ?? '';
          final timestamp = parseTimestamp(data['timestamp']);

          if (timestamp > 0 && timestamp < cutoff) continue;
          if (uid.isEmpty) continue;
          if (uid != currentUser.uid && !currentUser.following.contains(uid)) {
            continue;
          }
          if (!grouped.containsKey(uid)) grouped[uid] = [];
          grouped[uid]!.add({'id': doc.id, ...data});
        }

        final myStories = grouped[currentUser.uid] ?? [];
        final otherUsersUids = _buildSortedUids(grouped, currentUser.uid);

        return Container(
          height: 90,
          padding: const EdgeInsets.only(
            top: 8.0,
            bottom: 0.0,
            left: 16.0,
            right: 16.0,
          ),
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 1 + otherUsersUids.length,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final hasStories = myStories.isNotEmpty;
                      return GestureDetector(
                        onTap: () {
                          if (hasStories) {
                            onStoryTap(myStories);
                          } else {
                            onAddStoryTap();
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(right: 14.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Stack(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: hasStories
                                          ? const LinearGradient(
                                              colors: [
                                                Color(0xFFF9CE34),
                                                Color(0xFFEE2A7B),
                                                Color(0xFF6228D7),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            )
                                          : null,
                                      border: hasStories
                                          ? null
                                          : Border.all(
                                              color: Colors.grey.shade300,
                                              width: 1.5,
                                            ),
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: CustomAvatar(
radius: 22,
photoUrl: currentUser.photoUrl,
),
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: GestureDetector(
                                      onTap: onAddStoryTap,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFEC4899),
                                            shape: BoxShape.circle,
                                          ),
                                          padding: const EdgeInsets.all(2),
                                          child: const Icon(
                                            Icons.add,
                                            color: Colors.white,
                                            size: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const SizedBox(
                                width: 56,
                                child: Text(
                                  'Your Story',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.bold,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final creatorUid = otherUsersUids[index - 1];
                    final stories = grouped[creatorUid]!;
                    final firstStory = stories.first;
                    final String displayName =
                        firstStory['displayName'] ?? 'User';
                    final String? photoUrl = firstStory['photoUrl'];

                    return GestureDetector(
                      onTap: () => onStoryTap(stories),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 14.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFFF9CE34),
                                    Color(0xFFEE2A7B),
                                    Color(0xFF6228D7),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: CustomAvatar(
radius: 22,
photoUrl: photoUrl,
),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: 56,
                              child: Text(
                                displayName,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
