import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:call_project/features/home/presentation/providers/home_providers.dart';

class PostVideoPlayer extends ConsumerStatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  const PostVideoPlayer({super.key, required this.videoUrl, this.thumbnailUrl});

  @override
  ConsumerState<PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends ConsumerState<PostVideoPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _hasError = false;
  bool _isVideoFinished = false;

  // Visibility and lifecycle state tracking
  double _visibleFraction = 0.0;
  bool _isAppVisible = true;
  bool _isDisposed = false;
  double? _lastKnownAspectRatio;
  late final dynamic _visibilityNotifier;

  @override
  void initState() {
    super.initState();
    _visibilityNotifier = ref.read(feedVideoVisibilityProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    // Configure VisibilityDetector update interval (default is 500ms, set to 100ms for responsiveness)
    VisibilityDetectorController.instance.updateInterval = const Duration(
      milliseconds: 500,
    );
  }

  /// Called whenever the global feed mute state changes.
  void _applyMuteState(bool isMuted) {
    if (_isDisposed || !mounted) return;
    _controller?.setVolume(isMuted ? 0 : 1);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_isDisposed || !mounted) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _isAppVisible = false;
      _pauseVideo();
    } else if (state == AppLifecycleState.resumed) {
      _isAppVisible = true;
      _handleVisibilityChanged(_visibleFraction);
    }
  }

  void _onVideoPositionChanged() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final position = _controller!.value.position;
    final duration = _controller!.value.duration;

    if (duration > Duration.zero && position >= duration) {
      if (!_isVideoFinished && mounted) {
        setState(() {
          _isVideoFinished = true;
        });
      }
    } else {
      if (_isVideoFinished && mounted) {
        setState(() {
          _isVideoFinished = false;
        });
      }
    }
  }

  Future<void> _initializeCachedController() async {
    if (_isDisposed || !mounted) return;
    if (_isInitializing || _isInitialized || _controller != null) return;
    _isInitializing = true;
    try {
      final fileInfo = await DefaultCacheManager().getFileFromCache(
        widget.videoUrl,
      );
      if (_isDisposed || !mounted) return;

      final VideoPlayerController controller;
      if (fileInfo != null && fileInfo.file.existsSync()) {
        controller = VideoPlayerController.file(fileInfo.file);
      } else {
        controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl),
        );
      }
      await controller.initialize();
      if (mounted && !_isDisposed && _isInitializing) {
        setState(() {
          _controller = controller;
          _isInitialized = true;
          _isInitializing = false;
          _lastKnownAspectRatio = controller.value.aspectRatio;
        });
        _controller?.addListener(_onVideoPositionChanged);

        // Apply global mute state immediately on init
        final isMuted = ref.read(feedMuteProvider);
        _controller?.setVolume(isMuted ? 0 : 1);
        // Auto-play immediately if it's the active video
        final activeUrl = ref.read(activeFeedVideoProvider);
        if (activeUrl == widget.videoUrl) {
          _playVideo();
        }
      } else {
        controller.pause();
        controller.dispose();
      }
    } catch (e) {
      debugPrint(
        "Post cache video player initialize error, falling back to network: $e",
      );
      if (_isDisposed || !mounted) return;
      try {
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl),
        );
        await controller.initialize();
        if (mounted && !_isDisposed && _isInitializing) {
          setState(() {
            _controller = controller;
            _isInitialized = true;
            _isInitializing = false;
            _lastKnownAspectRatio = controller.value.aspectRatio;
          });
          _controller?.addListener(_onVideoPositionChanged);

          // Apply global mute state immediately on init
          final isMuted = ref.read(feedMuteProvider);
          _controller?.setVolume(isMuted ? 0 : 1);
          // Auto-play immediately if it's the active video
          if (ref.read(activeFeedVideoProvider) == widget.videoUrl) {
            _playVideo();
          }
        } else {
          controller.pause();
          controller.dispose();
        }
      } catch (err) {
        debugPrint("Network fallback failed for post video: $err");
        if (mounted && !_isDisposed) {
          setState(() {
            _hasError = true;
            _isInitializing = false;
          });
        }
      }
    }
  }

  void _playVideo() {
    if (_isDisposed || !mounted) return;

    // Prevent playback if story dialog is open
    final isStoryOpen = ref.read(isStoryDialogOpenProvider);
    if (isStoryOpen) {
      print('Prevented auto-play: Story dialog is currently open');
      return;
    }

    final controller = _controller;
    if (controller != null && _isInitialized) {
      // If we scroll back to a finished video, let it stay finished until user taps Watch Again
      if (!controller.value.isPlaying && !_isVideoFinished) {
        controller.setLooping(false);
        controller.play();
      }
    }
  }

  void _pauseVideo() {
    if (_isDisposed || !mounted) return;
    final controller = _controller;
    if (controller != null && _isInitialized) {
      if (controller.value.isPlaying) {
        controller.pause();
      }
    }
  }

  void _restartVideo() {
    if (_controller != null && _isInitialized) {
      _controller!.seekTo(Duration.zero);
      _controller!.play();
      setState(() {
        _isVideoFinished = false;
      });
    }
  }

  void _disposeController() {
    if (_isDisposed) return;
    final controller = _controller;
    _controller = null;
    _isInitialized = false;
    _isInitializing = false;
    controller?.removeListener(_onVideoPositionChanged);
    controller?.pause();
    controller?.dispose();
    if (mounted) {
      setState(() {});
    }
  }

  void _handleVisibilityChanged(double visibleFraction) {
    if (_isDisposed || !mounted) return;
    _visibleFraction = visibleFraction;

    // Update global registry
    Future.microtask(() {
      if (mounted) {
        ref.read(feedVideoVisibilityProvider.notifier).update((state) {
          final newState = Map<String, double>.from(state);
          if (visibleFraction <= 0.05) {
            newState.remove(widget.videoUrl);
          } else {
            newState[widget.videoUrl] = visibleFraction;
          }
          return newState;
        });
      }
    });

    if (!_isAppVisible) {
      _pauseVideo();
      return;
    }

    if (_visibleFraction >= 0.3) {
      // 30%+ visible: Start preloading / initialize controller if needed
      if (!_isInitialized && !_isInitializing) {
        _initializeCachedController();
      }
    } else if (_visibleFraction <= 0.2) {
      // If completely invisible (0.0), dispose the controller to save memory
      if (_visibleFraction == 0.0) {
        _disposeController();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    // Capture notifier before unmounting to prevent memory leak of visibility state
    final visibilityNotifier = _visibilityNotifier;
    final urlToRemove = widget.videoUrl;

    // Clean up registry when disposed
    Future.microtask(() {
      visibilityNotifier.update((state) {
        final newState = Map<String, double>.from(state);
        newState.remove(urlToRemove);
        return newState;
      });
    });

    _controller?.removeListener(_onVideoPositionChanged);
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMuted = ref.watch(feedMuteProvider);

    ref.listen(feedMuteProvider, (previous, next) {
      if (previous != next) {
        _applyMuteState(next);
      }
    });

    ref.listen(activeFeedVideoProvider, (previous, next) {
      if (previous != next) {
        if (next == widget.videoUrl) {
          if (_isInitialized) _playVideo();
        } else {
          _pauseVideo();
        }
      }
    });

    ref.listen(isStoryDialogOpenProvider, (previous, next) {
      if (previous != next) {
        if (next) {
          print('Story opened: Pausing feed video ${widget.videoUrl}');
          _pauseVideo();
        } else if (ref.read(activeFeedVideoProvider) == widget.videoUrl &&
            _isInitialized) {
          print('Story closed: Resuming feed video ${widget.videoUrl}');
          _playVideo();
        }
      }
    });

    // Also apply initial states immediately on build for the active video
    final activeVideoUrl = ref.read(activeFeedVideoProvider);
    if (activeVideoUrl == widget.videoUrl && _isInitialized) {
      // Don't call play directly inside build, use Future.microtask
      Future.microtask(() {
        if (mounted && !_isDisposed) _playVideo();
      });
    }

    if (_hasError) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'Failed to load video',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final controller = _controller;
    Widget content;

    if (controller == null || !_isInitialized) {
      if (_lastKnownAspectRatio != null) {
        content = AspectRatio(
          aspectRatio: _lastKnownAspectRatio!,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.thumbnailUrl != null &&
                  widget.thumbnailUrl!.isNotEmpty)
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: widget.thumbnailUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const SizedBox.shrink(),
                    errorWidget: (context, url, error) =>
                        const SizedBox.shrink(),
                  ),
                ),
              const Center(
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        content = widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty
            ? Stack(
                alignment: Alignment.center,
                children: [
                  CachedNetworkImage(
                    imageUrl: widget.thumbnailUrl!,
                    fit: BoxFit.contain, // Natural size dictates the Stack size
                    placeholder: (context, url) => const AspectRatio(
                      aspectRatio:
                          4 /
                          5, // Fallback vertical ratio while downloading thumb
                      child: Center(
                        child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
                      ),
                    ),
                    errorWidget: (context, url, error) => const AspectRatio(
                      aspectRatio: 4 / 5,
                      child: SizedBox.shrink(),
                    ),
                  ),
                  const Center(
                    child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
                  ),
                ],
              )
            : const AspectRatio(
                aspectRatio: 4 / 5,
                child: Center(
                  child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
                ),
              );
      }
    } else {
      content = AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video Player
            VideoPlayer(controller),

            // Watch Again Overlay
            if (_isVideoFinished)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: Center(
                    child: GestureDetector(
                      onTap: _restartVideo,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(100), // Perfect pill shape
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
                            SizedBox(width: 6),
                            Text(
                              'Watch Again',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Single tap handler to open full screen (only if not finished)
            if (!_isVideoFinished)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullScreenFeedVideoScreen(
                          videoUrl: widget.videoUrl,
                        ),
                      ),
                    );
                  },
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(),
                ),
              ),

            // ── Global Feed Mute Button (bottom-right) ──────────────────────
            if (!_isVideoFinished)
              Positioned(
                right: 10,
                bottom: 36,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    ref.read(feedMuteProvider.notifier).toggle();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return VisibilityDetector(
      key: Key(widget.videoUrl),
      onVisibilityChanged: (info) {
        _handleVisibilityChanged(info.visibleFraction);
      },
      child: content,
    );
  }
}

class FullScreenFeedVideoScreen extends ConsumerStatefulWidget {
  final String videoUrl;
  const FullScreenFeedVideoScreen({super.key, required this.videoUrl});

  @override
  ConsumerState<FullScreenFeedVideoScreen> createState() =>
      _FullScreenFeedVideoScreenState();
}

class _FullScreenFeedVideoScreenState
    extends ConsumerState<FullScreenFeedVideoScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isVideoFinished = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  void _onVideoPositionChanged() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final position = _controller!.value.position;
    final duration = _controller!.value.duration;

    if (duration > Duration.zero && position >= duration) {
      if (!_isVideoFinished && mounted) {
        setState(() {
          _isVideoFinished = true;
        });
      }
    } else {
      if (_isVideoFinished && mounted) {
        setState(() {
          _isVideoFinished = false;
        });
      }
    }
  }

  Future<void> _initVideo() async {
    try {
      final file = await DefaultCacheManager().getSingleFile(widget.videoUrl);
      _controller = VideoPlayerController.file(file);
    } catch (_) {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );
    }

    try {
      await _controller!.initialize();
      if (!mounted) {
        _controller!.dispose();
        return;
      }
      setState(() {
        _isInitialized = true;
      });
      _controller!.addListener(_onVideoPositionChanged);
      final isMuted = ref.read(feedMuteProvider);
      _controller!.setVolume(isMuted ? 0 : 1);
      _controller!.setLooping(false);
      _controller!.play();
    } catch (e) {
      debugPrint('Failed to load full screen video: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _restartVideo() {
    if (_controller != null && _isInitialized) {
      _controller!.seekTo(Duration.zero);
      _controller!.play();
      setState(() {
        _isVideoFinished = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoPositionChanged);
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMuted = ref.watch(feedMuteProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isInitialized) {
        _controller?.setVolume(isMuted ? 0 : 1);
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video Content
          Positioned.fill(
            child: _hasError
                ? const Center(
                    child: Text(
                      'Failed to load video',
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                : _isInitialized && _controller != null
                ? GestureDetector(
                    onTap: () {
                      if (_isVideoFinished) {
                        _restartVideo();
                        return;
                      }
                      if (_controller!.value.isPlaying) {
                        _controller!.pause();
                      } else {
                        _controller!.play();
                      }
                      setState(() {});
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                        if (!_controller!.value.isPlaying && !_isVideoFinished)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 50,
                            ),
                          ),

                        if (_isVideoFinished)
                          Container(
                            color: Colors.black.withValues(alpha: 0.3),
                            child: Center(
                              child: GestureDetector(
                                onTap: _restartVideo,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(100), // Perfect pill shape
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 15,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
                                      SizedBox(width: 6),
                                      Text(
                                        'Watch Again',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : const Center(
                    child: RepaintBoundary(
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
          ),

          // Back Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Mute Button
          if (_isInitialized && !_isVideoFinished)
            Positioned(
              right: 16,
              bottom: 36,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  ref.read(feedMuteProvider.notifier).toggle();
                },
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),

          // Progress bar at the bottom
          if (_isInitialized && _controller != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                _controller!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white70,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
        ],
      ),
    );
  }
}
