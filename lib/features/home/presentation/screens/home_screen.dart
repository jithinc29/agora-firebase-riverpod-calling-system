import 'dart:async';
import 'package:call_project/features/home/presentation/tabs/reels_tab.dart';
import 'package:call_project/features/home/presentation/tabs/chats_tab.dart';
import 'package:call_project/core/utils/time_utils.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:call_project/features/auth/repository/auth_repository.dart';
import 'package:call_project/features/users/data/repository/user_repository.dart';
import 'package:call_project/features/profile/presentation/screens/profile_screen.dart';
import 'package:call_project/features/users/presentation/screens/user_profile_screen.dart';
import 'package:call_project/features/notifications/presentation/screens/notification_screen.dart';
import 'package:call_project/features/notifications/data/repository/notification_repository.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/home/presentation/screens/search_bottom_sheet.dart';

import 'package:call_project/features/home/presentation/widgets/custom_bottom_nav_bar.dart';
import 'package:call_project/core/services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:call_project/features/home/presentation/screens/image_editor_screen.dart';
import 'package:call_project/features/home/presentation/screens/reel_upload_screen.dart';
import 'package:call_project/core/providers/refresh_provider.dart';
import 'package:call_project/features/home/presentation/utils/video_compression_service.dart';
import 'package:video_compress/video_compress.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:shimmer/shimmer.dart';
import 'package:call_project/features/home/presentation/screens/custom_gallery_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:call_project/features/profile/presentation/screens/settings_screen.dart';

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

// Global mute state for Feed section only (does NOT affect Reels)
class _FeedMuteNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
  void set(bool value) => state = value;
}

final feedMuteProvider = NotifierProvider<_FeedMuteNotifier, bool>(
  _FeedMuteNotifier.new,
);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  Timer? _heartbeatTimer;
  final bool _isDeleting = false;
  int _currentTabIndex = 1;
  bool _isMenuOpen = false;
  int _activeReelIndex = 0;
  final _postController = TextEditingController();
  bool _isPosting = false;
  File? _inlinePostMediaFile;
  String? _inlinePostMediaType;
  final Set<String> _hiddenPostIds = {};
  DateTime? _lastBackPressTime;

  // Feed Posts Pagination State
  final List<DocumentSnapshot> _feedPosts = [];
  DocumentSnapshot? _lastFeedPostDoc;
  bool _isLoadingFeedPosts = false;
  bool _hasMoreFeedPosts = true;
  bool _isShowingSuggestedFeed = false;
  late final ScrollController _feedScrollController;

  // Reels Pagination & Preload State
  final List<DocumentSnapshot> _reelsDocs = [];
  DocumentSnapshot? _lastReelDoc;
  bool _isLoadingReels = false;
  bool _hasMoreReels = true;
  bool _isShowingSuggestedReels = false;
  final Map<int, VideoPlayerController> _reelsControllers = {};
  // Indices currently being asynchronously initialised – prevents double-init races
  final Set<int> _reelsInitializing = {};
  // PageController so we can imperatively control the reels PageView
  late PageController _reelsPageController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reelsPageController = PageController();
    _startHeartbeat();

    // Initialize feed scroll controller and pagination
    _feedScrollController = ScrollController();
    _feedScrollController.addListener(_onFeedScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSystemAlertWindowPermission();
    });
  }

  Future<void> _checkSystemAlertWindowPermission() async {
    if (await Permission.systemAlertWindow.isDenied) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.phone_in_talk, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Don\'t miss calls!'),
            ],
          ),
          content: const Text(
            'To receive full-screen incoming calls even when your phone is locked, you must enable the "Display over other apps" permission.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Not Now',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                await Permission.systemAlertWindow.request();
                if (mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text(
                'Enable Permission',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // Pause all reels when app goes to background
      for (final c in _reelsControllers.values) {
        if (c.value.isInitialized && c.value.isPlaying) {
          c.pause();
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      // Resume only the active reel when returning to foreground
      if (_currentTabIndex == 2) {
        final active = _reelsControllers[_activeReelIndex];
        if (active != null &&
            active.value.isInitialized &&
            !active.value.isPlaying) {
          active.play();
        }
      }
    }
  }

  void _startHeartbeat() {
    _updatePresence();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _updatePresence();
    });
  }

  void _updatePresence() async {
    if (_isDeleting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && !_isDeleting) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'isOnline': true,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
        }, SetOptions(merge: true));
      }
    }
  }

  void _onFeedScroll() {
    if (_feedScrollController.position.pixels >=
        _feedScrollController.position.maxScrollExtent - 200) {
      _fetchFeedPostsPage();
    }
  }

  Future<void> _fetchFeedPostsPage({bool isRefresh = false}) async {
    if (isRefresh) {
      _lastFeedPostDoc = null;
      _hasMoreFeedPosts = true;
      _isShowingSuggestedFeed = false;
      _feedPosts.clear();
    }

    if (_isLoadingFeedPosts || !_hasMoreFeedPosts) return;

    setState(() {
      _isLoadingFeedPosts = true;
    });

    try {
      final currentUserData = ref.read(currentUserDataProvider);
      final currentUser = currentUserData.value;
      if (currentUser == null) return;

      final followingUids = currentUser.following;
      final currentUid = currentUser.uid;

      int newPostsCount = 0;

      while (newPostsCount < 5 && _hasMoreFeedPosts) {
        Query query = FirebaseFirestore.instance
            .collection('posts')
            .orderBy('timestamp', descending: true)
            .limit(10);

        if (_lastFeedPostDoc != null) {
          query = query.startAfterDocument(_lastFeedPostDoc!);
        }

        final snapshot = await query.get();
        if (snapshot.docs.isNotEmpty) {
          _lastFeedPostDoc = snapshot.docs.last;

          final validDocs = snapshot.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['isHidden'] == true) return false;
            if (_isShowingSuggestedFeed) return true;
            final postUid = data['uid'] as String?;
            return postUid == currentUid || followingUids.contains(postUid);
          }).toList();

          if (validDocs.isNotEmpty) {
            setState(() {
              for (var doc in validDocs) {
                if (!_feedPosts.any((existing) => existing.id == doc.id)) {
                  _feedPosts.add(doc);
                }
              }
            });
            newPostsCount += validDocs.length;
          }
        }

        if (snapshot.docs.length < 10) {
          _hasMoreFeedPosts = false;
        }
      }

      if (_feedPosts.isEmpty &&
          !_hasMoreFeedPosts &&
          !_isShowingSuggestedFeed) {
        _isShowingSuggestedFeed = true;
        _hasMoreFeedPosts = true;
        _lastFeedPostDoc = null;
        setState(() {
          _isLoadingFeedPosts = false;
        });
        return _fetchFeedPostsPage();
      }
    } catch (e) {
      debugPrint("Error fetching feed posts: $e");
    } finally {
      setState(() {
        _isLoadingFeedPosts = false;
      });
    }
  }

  Future<void> _fetchReelsPage({bool isRefresh = false}) async {
    if (isRefresh) {
      _lastReelDoc = null;
      _hasMoreReels = true;
      _isShowingSuggestedReels = false;
      _reelsInitializing.clear(); // cancel pending inits
      for (final c in _reelsControllers.values) {
        c.pause(); // silence first to avoid audio bleed
        c.dispose();
      }
      _reelsControllers.clear();
      _reelsDocs.clear();
      _activeReelIndex = 0;
      if (_reelsPageController.hasClients) {
        _reelsPageController.jumpToPage(0);
      }
    }

    if (_isLoadingReels || !_hasMoreReels) return;

    setState(() {
      _isLoadingReels = true;
    });

    try {
      final currentUserData = ref.read(currentUserDataProvider);
      final currentUser = currentUserData.value;
      if (currentUser == null) return;

      final followingUids = currentUser.following;
      final currentUid = currentUser.uid;

      int newReelsCount = 0;

      while (newReelsCount < 5 && _hasMoreReels) {
        Query query = FirebaseFirestore.instance
            .collection('reels')
            .orderBy('timestamp', descending: true)
            .limit(10);

        if (_lastReelDoc != null) {
          query = query.startAfterDocument(_lastReelDoc!);
        }

        final snapshot = await query.get();
        if (snapshot.docs.isNotEmpty) {
          _lastReelDoc = snapshot.docs.last;

          final validDocs = snapshot.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['isHidden'] == true) return false;
            if (_isShowingSuggestedReels) return true;
            final reelUid = data['uid'] as String?;
            return reelUid == currentUid || followingUids.contains(reelUid);
          }).toList();

          if (validDocs.isNotEmpty) {
            setState(() {
              for (var doc in validDocs) {
                if (!_reelsDocs.any((existing) => existing.id == doc.id)) {
                  _reelsDocs.add(doc);
                }
              }
            });
            newReelsCount += validDocs.length;
          }
        }

        if (snapshot.docs.length < 10) {
          _hasMoreReels = false;
        }
      }

      if (_reelsDocs.isEmpty && !_hasMoreReels && !_isShowingSuggestedReels) {
        _isShowingSuggestedReels = true;
        _hasMoreReels = true;
        _lastReelDoc = null;
        setState(() {
          _isLoadingReels = false;
        });
        return _fetchReelsPage();
      }

      _manageReelsControllers();
    } catch (e) {
      debugPrint("Error fetching reels: $e");
    } finally {
      setState(() {
        _isLoadingReels = false;
      });
    }
  }

  void _manageReelsControllers() async {
    // Keep current, one ahead, and one behind (3-window)
    final Set<int> keepIndices = {
      if (_activeReelIndex > 0) _activeReelIndex - 1,
      _activeReelIndex,
      _activeReelIndex + 1,
    };

    final reels = _getActiveReelsData();

    // ── STEP 1: Dispose controllers that are no longer needed ──────────────
    final keys = List<int>.from(_reelsControllers.keys);
    for (final idx in keys) {
      if (!keepIndices.contains(idx) || idx >= reels.length || idx < 0) {
        final old = _reelsControllers.remove(idx);
        _reelsInitializing.remove(idx);
        old?.pause(); // silence before dispose to prevent audio bleed
        old?.dispose();
      }
    }

    // ── STEP 2: Pause ALL non-active controllers first ─────────────────────
    for (final entry in _reelsControllers.entries) {
      if (entry.key != _activeReelIndex) {
        final c = entry.value;
        if (c.value.isInitialized) {
          if (c.value.isPlaying) c.pause();
          c.seekTo(Duration.zero);
          c.pause();
          c.setVolume(0);
        }
      }
    }

    // ── STEP 3: Start initializing controllers that are missing ───────────
    for (int i = 0; i < reels.length; i++) {
      if (!keepIndices.contains(i)) continue;

      final data = reels[i];
      final url = data['videoUrl'] as String?;
      if (url == null || url.isEmpty) continue;

      final existing = _reelsControllers[i];
      if (existing != null) {
        // Already have a controller – play only the active one
        if (existing.value.isInitialized) {
          if (i == _activeReelIndex && !existing.value.isPlaying) {
            if (_currentTabIndex == 2) {
              existing.play();
              existing.setLooping(true);
            }
          } else {}
        } else {}
        continue;
      }

      // Guard against duplicate async inits for the same slot
      if (_reelsInitializing.contains(i)) {
        continue;
      }

      _initializeReelController(i, url);
    }
  }

  void _pauseActiveReel() {
    _reelsControllers[_activeReelIndex]?.pause();
  }

  void _resumeActiveReel() {
    if (_currentTabIndex == 2) {
      _reelsControllers[_activeReelIndex]?.play();
    }
  }

  Future<void> _initializeReelController(int index, String url) async {
    _reelsInitializing.add(index);
    VideoPlayerController? controller;
    try {
      // ── Try cached file first ────────────────────────────────────────────
      try {
        final file = await DefaultCacheManager().getSingleFile(url);
        controller = VideoPlayerController.file(file);
      } catch (_) {
        controller = VideoPlayerController.networkUrl(Uri.parse(url));
      }

      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        _reelsInitializing.remove(index);
        return;
      }

      // Discard if the slot was evicted while we were awaiting
      final stillWanted =
          _reelsControllers.containsKey(index) ||
          _reelsInitializing.contains(index);
      if (!stillWanted) {
        controller.dispose();
        return;
      }

      // Safely swap — dispose any stale placeholder
      final old = _reelsControllers[index];
      if (old != null && old != controller) {
        old.pause();
        old.dispose();
      }
      _reelsControllers[index] = controller;
      _reelsInitializing.remove(index);

      // Play only if this is still the active reel, the tab is visible, and story dialog is closed
      final isStoryOpen = ref.read(isStoryDialogOpenProvider);
      final shouldPlay =
          index == _activeReelIndex && _currentTabIndex == 2 && !isStoryOpen;
      if (shouldPlay) {
        controller.setLooping(true);
        controller.play();
      }

      if (mounted) setState(() {});
    } catch (e) {
      controller?.dispose();
      _reelsInitializing.remove(index);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _postController.dispose();
    _feedScrollController.dispose();
    _reelsPageController.dispose();
    // Silence + dispose all reels controllers
    for (final c in _reelsControllers.values) {
      c.pause();
      c.dispose();
    }
    _reelsControllers.clear();
    _reelsInitializing.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(mediaRefreshProvider, (previous, next) {
      if (previous != next) {
        _fetchReelsPage(isRefresh: true);
        _fetchFeedPostsPage(isRefresh: true);
      }
    });

    ref.listen(isStoryDialogOpenProvider, (previous, next) {
      if (previous != next) {
        if (next) {
          _pauseActiveReel();
        } else {
          _resumeActiveReel();
        }
      }
    });

    final currentUserData = ref.watch(currentUserDataProvider);

    // Initial fetch trigger: wait until user data is loaded to fetch feed posts
    if (currentUserData.value != null &&
        _feedPosts.isEmpty &&
        _hasMoreFeedPosts &&
        !_isLoadingFeedPosts) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchFeedPostsPage();
      });
    }

    return currentUserData.when(
      data: (user) {
        if (user == null || _isDeleting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final usersAsync = ref.watch(allUsersProvider);
        final currentUser = FirebaseAuth.instance.currentUser;

        return PopScope(
          canPop: false,
          onPopInvoked: (didPop) async {
            if (didPop) return;

            final now = DateTime.now();
            if (_lastBackPressTime == null ||
                now.difference(_lastBackPressTime!) >
                    const Duration(seconds: 2)) {
              _lastBackPressTime = now;

              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Tap again to exit',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  backgroundColor: const Color(0xFF323232),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.only(
                    bottom: 80,
                    left: 64,
                    right: 64,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                  duration: const Duration(seconds: 2),
                ),
              );
            } else {
              SystemNavigator.pop();
            }
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: Stack(
              children: [
                // Main Tab Content
                Positioned.fill(
                  child: IndexedStack(
                    index: _currentTabIndex,
                    children: [
                      // Index 0: Feeds Tab
                      SafeArea(
                        bottom: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(context, ref, user, 0),
                            const SizedBox(height: 4),
                            Expanded(child: _buildFeedsTab(user)),
                          ],
                        ),
                      ),
                      // Index 1: Chats Tab
                      SafeArea(
                        bottom: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(context, ref, user, 1),
                            const SizedBox(height: 4),
                            Expanded(
                              child: _buildChatsTab(
                                usersAsync,
                                currentUser,
                                user,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Index 2: Reels Tab (No SafeArea, No Header)
                      _buildReelsTab(user),
                      // Index 3: Profile Tab
                      SafeArea(
                        bottom: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(context, ref, user, 3),
                            const SizedBox(height: 4),
                            Expanded(child: ProfileScreen(isEmbedded: true)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Custom Floating Bottom Navigation Bar
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  top: _isMenuOpen
                      ? 0
                      : null, // Expand constraints when open to register tap gestures on full screen
                  child: CustomBottomNavBar(
                    currentIndex: _currentTabIndex,
                    isMenuOpen: _isMenuOpen,
                    onMenuToggle: () {
                      setState(() {
                        _isMenuOpen = !_isMenuOpen;
                      });

                      if (_currentTabIndex == 2) {
                        final controller = _reelsControllers[_activeReelIndex];
                        if (controller != null &&
                            controller.value.isInitialized) {
                          if (_isMenuOpen) {
                            controller.pause();
                          } else {
                            controller.play();
                          }
                        }
                      }
                    },
                    onMenuClose: () {
                      setState(() {
                        _isMenuOpen = false;
                      });

                      if (_currentTabIndex == 2) {
                        final controller = _reelsControllers[_activeReelIndex];
                        if (controller != null &&
                            controller.value.isInitialized) {
                          controller.play();
                        }
                      }
                    },
                    onTap: (index) {
                      setState(() {
                        _currentTabIndex = index;
                      });
                      ref.read(currentTabIndexProvider.notifier).state = index;
                      if (index == 2) {
                        // Entering Reels tab

                        // ── KEY FIX ────────────────────────────────────────────────────────────
                        // Recreate the PageController with the correct initialPage.
                        // This completely prevents the `PageView` from building `initialPage: 0`
                        // on the first frame and then jumping to `_activeReelIndex` on the next frame,
                        // which was causing a massive layout and raster spike (rendering two videos instantly).
                        _reelsPageController.dispose();
                        _reelsPageController = PageController(
                          initialPage: _activeReelIndex,
                        );

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          // After the jump, ensure only the active controller is playing
                          for (final entry in _reelsControllers.entries) {
                            if (entry.key != _activeReelIndex) {
                              if (entry.value.value.isInitialized &&
                                  entry.value.value.isPlaying) {
                                entry.value.pause();
                              }
                            } else {
                              if (entry.value.value.isInitialized) {
                                entry.value.seekTo(Duration.zero);
                                entry.value.play();
                              }
                            }
                          }
                          _manageReelsControllers();
                        });

                        if (_reelsDocs.isEmpty) {
                          _fetchReelsPage();
                        }
                        // Note: _manageReelsControllers() is now called inside
                        // the postFrameCallback above (after page jump) when
                        // docs exist. For fresh load it's called by _fetchReelsPage.
                      } else {
                        // Leaving the reels tab - silence ALL controllers immediately and reset position
                        for (final c in _reelsControllers.values) {
                          if (c.value.isInitialized) {
                            if (c.value.isPlaying) c.pause();
                            c.seekTo(Duration.zero);
                          }
                        }
                      }
                    },
                    onCreatePostTap: () => _handleCreatePostTap(context, user),
                    onCreateReelTap: () => _showCreateReelDialog(context, user),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  Widget _buildChatsTab(
    AsyncValue<List<UserModel>> usersAsync,
    User? currentUser,
    UserModel user,
  ) {
    return ChatsTab(
      usersAsync: usersAsync,
      currentUser: currentUser,
      user: user,
      onPauseReels: _pauseActiveReel,
      formatLastSeen: _formatLastSeen,
    );
  }

  Widget _buildFeedsTab(UserModel currentUser) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.background),
      child: RefreshIndicator(
        onRefresh: () => _fetchFeedPostsPage(isRefresh: true),
        color: AppColors.primary,
        child: Column(
          children: [
            // Post Creator Card
            _buildPostCreatorCard(currentUser),
            // Feed List
            Expanded(
              child:
                  _feedPosts.isEmpty &&
                      (_isLoadingFeedPosts || _hasMoreFeedPosts)
                  ? const Center(child: CircularProgressIndicator())
                  : _feedPosts.isEmpty
                  ? const Center(
                      child: Text(
                        'No posts yet. Be the first to share!',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      controller: _feedScrollController,
                      padding: const EdgeInsets.only(top: 4, bottom: 78),
                      itemCount:
                          _feedPosts.length +
                          (_isLoadingFeedPosts ? 1 : 0) +
                          (_isShowingSuggestedFeed ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_isShowingSuggestedFeed && index == 0) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Text(
                              'Suggested for you',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          );
                        }

                        final actualIndex = _isShowingSuggestedFeed
                            ? index - 1
                            : index;

                        if (actualIndex == _feedPosts.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final doc = _feedPosts[actualIndex];
                        if (_hiddenPostIds.contains(doc.id)) {
                          return const SizedBox.shrink();
                        }
                        return _buildPostCard(doc, currentUser);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCreatorCard(UserModel currentUser) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.only(left: 10, right: 10, top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundImage: currentUser.photoUrl != null
                    ? CachedNetworkImageProvider(currentUser.photoUrl!)
                    : null,
                child: currentUser.photoUrl == null
                    ? Text(
                        currentUser.displayName.isNotEmpty
                            ? currentUser.displayName[0].toUpperCase()
                            : '?',
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _postController,
                  maxLines: 4,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: "What's on your mind?",
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _pickInlinePostMedia(
                  ImageSource.gallery,
                  'image',
                  currentUser,
                ),
                icon: const Icon(
                  Icons.image_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Add Photo',
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _pickInlinePostMedia(
                  ImageSource.gallery,
                  'video',
                  currentUser,
                ),
                icon: const Icon(
                  Icons.videocam_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Add Video',
              ),
              const SizedBox(width: 12),
              _isPosting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: () => _createPost(currentUser),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Post',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
            ],
          ),
          if (_inlinePostMediaFile != null) ...[
            const SizedBox(height: 8),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _inlinePostMediaType == 'image'
                      ? Image.file(
                          _inlinePostMediaFile!,
                          height: 100,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          height: 100,
                          width: double.infinity,
                          color: Colors.black,
                          child: const Center(
                            child: Icon(
                              Icons.video_library_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _inlinePostMediaFile = null;
                        _inlinePostMediaType = null;
                      });
                    },
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(3),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<String?> _uploadFile(File file, String folder) async {
    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final refStorage = FirebaseStorage.instance.ref().child(
        '$folder/$fileName',
      );
      final uploadTask = await refStorage.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint("Storage Upload Error: $e");
      return null;
    }
  }

  Future<void> _pickInlinePostMedia(
    ImageSource source,
    String type,
    UserModel currentUser,
  ) async {
    final RequestType requestType = type == 'image'
        ? RequestType.image
        : RequestType.video;

    File? file;
    if (source == ImageSource.camera) {
      final picker = ImagePicker();
      if (type == 'image') {
        final xfile = await picker.pickImage(source: source, imageQuality: 70);
        if (xfile != null) file = File(xfile.path);
      } else {
        final xfile = await picker.pickVideo(source: source);
        if (xfile != null) file = File(xfile.path);
      }
    } else {
      final result = await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              CustomGalleryPickerScreen(requestType: requestType),
        ),
      );
      if (result != null && result['file'] is File) {
        file = result['file'] as File;
      }
    }

    if (file != null && mounted) {
      if (type == 'image') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageEditorScreen(
              imageFile: file!,
              currentUser: currentUser,
              mode: 'post',
              initialCaption: _postController.text,
              onSuccess: () {
                _postController.clear();
                _fetchFeedPostsPage(isRefresh: true);
                ref.read(mediaRefreshProvider.notifier).state++;
              },
            ),
          ),
        );
      } else if (type == 'video') {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => ReelUploadScreen(
              videoFile: file!,
              currentUser: currentUser,
              mode: 'post', // Upload as video post
            ),
          ),
        );
        if (result == true && context.mounted) {
          _postController.clear();
          _fetchFeedPostsPage(isRefresh: true);
          ref.read(mediaRefreshProvider.notifier).state++;
        }
      }
    }
  }

  void _createPost(UserModel currentUser) async {
    final text = _postController.text.trim();
    if (text.isEmpty && _inlinePostMediaFile == null) return;

    setState(() => _isPosting = true);

    try {
      String? mediaUrl;
      String? type;
      String? thumbnailUrl;

      if (_inlinePostMediaFile != null) {
        File fileToUpload = _inlinePostMediaFile!;
        if (_inlinePostMediaType == 'video') {
          // Compress video client-side before uploading
          if (context.mounted) {
            fileToUpload = await VideoCompressionService.compressVideo(
              context,
              _inlinePostMediaFile!,
            );
          }

          // Generate thumbnail
          final thumbnailFile = await VideoCompress.getFileThumbnail(
            fileToUpload.path,
            quality: 50,
          );
          final String thumbFileName =
              '${DateTime.now().millisecondsSinceEpoch}_post_thumb.jpg';
          final refThumb = FirebaseStorage.instance.ref().child(
            'posts_thumbnail/$thumbFileName',
          );
          final uploadThumbTask = await refThumb.putFile(thumbnailFile);
          thumbnailUrl = await uploadThumbTask.ref.getDownloadURL();
        }

        final folder = _inlinePostMediaType == 'video'
            ? 'posts_video'
            : 'posts_image';
        mediaUrl = await _uploadFile(fileToUpload, folder);
        if (mediaUrl == null) {
          throw Exception("Media upload failed");
        }
        type = _inlinePostMediaType;
      }

      await FirebaseFirestore.instance.collection('posts').add({
        'uid': currentUser.uid,
        'displayName': currentUser.displayName,
        'photoUrl': currentUser.photoUrl,
        'text': text,
        'mediaUrl': mediaUrl,
        'thumbnailUrl': thumbnailUrl,
        'type': type,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': <String>[],
      });
      _postController.clear();
      setState(() {
        _inlinePostMediaFile = null;
        _inlinePostMediaType = null;
      });
      if (mounted) {
        FocusScope.of(context).unfocus();
        TopNotificationService.showSuccess(
          context,
          'Post shared successfully!',
        );
        _fetchFeedPostsPage(isRefresh: true);
        ref.read(mediaRefreshProvider.notifier).state++;
      }
    } catch (e) {
      if (mounted) {
        TopNotificationService.showError(context, 'Failed to post: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  Widget _buildPostCard(
    DocumentSnapshot initialPostDoc,
    UserModel currentUser,
  ) {
    final data = initialPostDoc.data() as Map<String, dynamic>? ?? {};
    final String displayName = data['displayName'] ?? 'Anonymous';
    final String? photoUrl = data['photoUrl'];
    final String text = data['text'] ?? '';
    final int timestampMillis = parseTimestamp(data['timestamp']);
    final DateTime? timestampDate = timestampMillis > 0
        ? DateTime.fromMillisecondsSinceEpoch(timestampMillis)
        : null;
    final String? type = data['type'];
    final String? mediaUrl = data['mediaUrl'];
    final String? thumbnailUrl = data['thumbnailUrl'];

    String timeAgo = 'Just now';
    if (timestampDate != null) {
      final diff = DateTime.now().difference(timestampDate);
      if (diff.inMinutes < 1) {
        timeAgo = 'Just now';
      } else if (diff.inMinutes < 60) {
        timeAgo = '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        timeAgo = '${diff.inHours}h ago';
      } else {
        timeAgo = '${diff.inDays}d ago';
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Row
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundImage: photoUrl != null
                    ? CachedNetworkImageProvider(photoUrl)
                    : null,
                child: photoUrl == null
                    ? Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      timeAgo,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _showPostOptionsMenu(
                  context,
                  initialPostDoc,
                  currentUser.uid,
                ),
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: AppColors.textSecondary,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Post Text
          if (text.isNotEmpty) ...[
            Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Post Media
          if (mediaUrl != null && mediaUrl.isNotEmpty) ...[
            _buildPostCardMedia(type, mediaUrl, thumbnailUrl),
            const SizedBox(height: 8),
          ],
          // Action Row (Like, Comment, etc) - DIVIDER REMOVED as requested
          Row(
            children: [
              StreamBuilder<DocumentSnapshot>(
                stream: initialPostDoc.reference.snapshots(),
                builder: (context, snapshot) {
                  final postDoc = snapshot.data ?? initialPostDoc;
                  final postData =
                      postDoc.data() as Map<String, dynamic>? ?? {};
                  final List<dynamic> likes = postData['likes'] ?? [];
                  final isLiked = likes.contains(currentUser.uid);
                  final likeCount = likes.length;

                  return GestureDetector(
                    onTap: () {
                      final updatedLikes = List<String>.from(likes);
                      if (isLiked) {
                        updatedLikes.remove(currentUser.uid);
                      } else {
                        updatedLikes.add(currentUser.uid);
                      }
                      postDoc.reference.update({'likes': updatedLikes});
                    },
                    child: Row(
                      children: [
                        Icon(
                          isLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: isLiked ? Colors.red : AppColors.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$likeCount',
                          style: TextStyle(
                            color: isLiked
                                ? Colors.red
                                : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: () => _showCommentsBottomSheet(
                  context,
                  initialPostDoc,
                  currentUser,
                ),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AppColors.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    StreamBuilder<QuerySnapshot>(
                      stream: initialPostDoc.reference
                          .collection('comments')
                          .snapshots(),
                      builder: (context, snapshot) {
                        final count = snapshot.hasData
                            ? snapshot.data!.docs.length
                            : 0;
                        return Text(
                          '$count',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {
                  final link =
                      'https://callingapp.page.link/post/${initialPostDoc.id}';
                  Clipboard.setData(ClipboardData(text: link));
                  TopNotificationService.showSuccess(
                    context,
                    'Post link copied to clipboard!',
                  );
                },
                icon: const Icon(
                  Icons.share_outlined,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPostCardMedia(
    String? type,
    String mediaUrl,
    String? thumbnailUrl,
  ) {
    if (type == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
          imageUrl: mediaUrl,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              Container(height: 200, color: Colors.black12),
          errorWidget: (context, url, error) => Container(
            height: 200,
            color: Colors.black12,
            child: const Center(
              child: Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        ),
      );
    } else if (type == 'video') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.black,
          child: PostVideoPlayer(
            videoUrl: mediaUrl,
            thumbnailUrl: thumbnailUrl,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _showPostOptionsMenu(
    BuildContext context,
    DocumentSnapshot postDoc,
    String currentUserId,
  ) {
    final data = postDoc.data() as Map<String, dynamic>? ?? {};
    final String authorId = data['uid'] ?? '';
    final bool isOwner = authorId == currentUserId;

    // Capture outer context BEFORE the bottom-sheet builder shadows it with
    // its own 'context' parameter. This ensures we always use a valid,
    // mounted context for dialogs and notifications that appear after the
    // bottom sheet is dismissed.
    final outerContext = context;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (isOwner)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                  ),
                  title: const Text(
                    'Delete Post',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext); // close bottom sheet
                    _confirmDeletePost(
                      outerContext,
                      postDoc,
                    ); // use outer context for dialog
                  },
                ),
              if (isOwner)
                ListTile(
                  leading: Icon(
                    data['isHidden'] == true
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_outlined,
                    color: AppColors.textPrimary,
                  ),
                  title: Text(
                    data['isHidden'] == true ? 'Unhide Post' : 'Archive Post',
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final bool isHidden = data['isHidden'] == true;
                    await postDoc.reference.update({'isHidden': !isHidden});
                    ref.read(mediaRefreshProvider.notifier).state++;
                    if (outerContext.mounted) {
                      TopNotificationService.showSuccess(
                        outerContext,
                        isHidden
                            ? 'Post unhidden and visible in feed'
                            : 'Post archived to your profile',
                      );
                    }
                  },
                )
              else
                ListTile(
                  leading: const Icon(
                    Icons.visibility_off_outlined,
                    color: AppColors.textPrimary,
                  ),
                  title: const Text(
                    'Hide Post',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() {
                      _hiddenPostIds.add(postDoc.id);
                    });
                    if (outerContext.mounted) {
                      TopNotificationService.showSuccess(
                        outerContext,
                        'Post hidden',
                      );
                    }
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeletePost(BuildContext context, DocumentSnapshot postDoc) {
    // 'context' here is the outer (feed list) context — always valid.
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Delete Post',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Are you sure you want to delete this post permanently? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final data = postDoc.data() as Map<String, dynamic>? ?? {};
                final mediaUrl = data['mediaUrl'] as String?;
                if (mediaUrl != null && mediaUrl.isNotEmpty) {
                  try {
                    final storageRef = FirebaseStorage.instance.refFromURL(
                      mediaUrl,
                    );
                    await storageRef.delete();
                  } catch (e) {
                    debugPrint('Failed to delete media from storage: $e');
                  }
                }
                await postDoc.reference.delete();
                // Remove post from the local list immediately for instant UI feedback
                // then refresh the full feed to stay in sync with Firestore.
                if (mounted) {
                  setState(() {
                    _feedPosts.removeWhere((doc) => doc.id == postDoc.id);
                  });
                  // Full refresh ensures pagination cursors stay consistent.
                  await _fetchFeedPostsPage(isRefresh: true);
                }
                if (context.mounted) {
                  TopNotificationService.showSuccess(
                    context,
                    'Post deleted successfully',
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  TopNotificationService.showError(
                    context,
                    'Failed to delete post: $e',
                  );
                }
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showCommentsBottomSheet(
    BuildContext context,
    DocumentSnapshot postDoc,
    UserModel currentUser,
  ) {
    final textController = TextEditingController();
    final focusNode = FocusNode();
    String? replyToCommentId;
    String? replyToUsername;

    final commentsStream = postDoc.reference
        .collection('comments')
        .orderBy('timestamp', descending: false)
        .snapshots();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    'Comments',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: commentsStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Error: ${snapshot.error}'),
                          );
                        }
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final commentDocs = snapshot.data?.docs ?? [];
                        if (commentDocs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No comments yet. Start the conversation!',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          );
                        }

                        final parentComments = commentDocs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return data['parentId'] == null ||
                              (data['parentId'] as String).isEmpty;
                        }).toList();

                        final replies = commentDocs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return data['parentId'] != null &&
                              (data['parentId'] as String).isNotEmpty;
                        }).toList();

                        final Map<String, List<DocumentSnapshot>>
                        repliesByParent = {};
                        for (var reply in replies) {
                          final data = reply.data() as Map<String, dynamic>;
                          final parentId = data['parentId'] as String;
                          repliesByParent
                              .putIfAbsent(parentId, () => [])
                              .add(reply);
                        }

                        final currentUserUid = currentUser.uid;
                        final postAuthorUid =
                            (postDoc.data() as Map<String, dynamic>?)?['uid']
                                as String?;

                        final List<Widget> listItems = [];
                        for (var parent in parentComments) {
                          final parentData =
                              parent.data() as Map<String, dynamic>? ?? {};
                          final parentLikes =
                              parentData['likes'] as List<dynamic>? ?? [];
                          listItems.add(
                            _buildCommentItem(
                              commentDoc: parent,
                              isReply: false,
                              isLiked: parentLikes.contains(currentUserUid),
                              likeCount: parentLikes.length,
                              onLikeTap: () {
                                final updatedLikes = List<String>.from(
                                  parentLikes.map((e) => e.toString()),
                                );
                                if (updatedLikes.contains(currentUserUid)) {
                                  updatedLikes.remove(currentUserUid);
                                } else {
                                  updatedLikes.add(currentUserUid);
                                }
                                parent.reference.update({
                                  'likes': updatedLikes,
                                });
                              },
                              onLongPress: () => _showCommentOptions(
                                context,
                                parent,
                                currentUserUid,
                                postAuthorUid,
                              ),
                              onReplyTap: () {
                                final name =
                                    parentData['displayName'] ?? 'Anonymous';
                                setState(() {
                                  replyToCommentId = parent.id;
                                  replyToUsername = name;
                                  textController.text = '@$name ';
                                  textController.selection =
                                      TextSelection.fromPosition(
                                        TextPosition(
                                          offset: textController.text.length,
                                        ),
                                      );
                                });
                                focusNode.requestFocus();
                              },
                            ),
                          );

                          final parentReplies =
                              repliesByParent[parent.id] ?? [];
                          for (var reply in parentReplies) {
                            final replyData =
                                reply.data() as Map<String, dynamic>? ?? {};
                            final replyLikes =
                                replyData['likes'] as List<dynamic>? ?? [];
                            listItems.add(
                              Padding(
                                padding: const EdgeInsets.only(left: 36.0),
                                child: _buildCommentItem(
                                  commentDoc: reply,
                                  isReply: true,
                                  isLiked: replyLikes.contains(currentUserUid),
                                  likeCount: replyLikes.length,
                                  onLikeTap: () {
                                    final updatedLikes = List<String>.from(
                                      replyLikes.map((e) => e.toString()),
                                    );
                                    if (updatedLikes.contains(currentUserUid)) {
                                      updatedLikes.remove(currentUserUid);
                                    } else {
                                      updatedLikes.add(currentUserUid);
                                    }
                                    reply.reference.update({
                                      'likes': updatedLikes,
                                    });
                                  },
                                  onLongPress: () => _showCommentOptions(
                                    context,
                                    reply,
                                    currentUserUid,
                                    postAuthorUid,
                                  ),
                                  onReplyTap: () {
                                    final name =
                                        replyData['displayName'] ?? 'Anonymous';
                                    setState(() {
                                      replyToCommentId = parent.id;
                                      replyToUsername = name;
                                      textController.text = '@$name ';
                                      textController.selection =
                                          TextSelection.fromPosition(
                                            TextPosition(
                                              offset:
                                                  textController.text.length,
                                            ),
                                          );
                                    });
                                    focusNode.requestFocus();
                                  },
                                ),
                              ),
                            );
                          }
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: listItems.length,
                          itemBuilder: (context, index) => listItems[index],
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  if (replyToUsername != null)
                    Container(
                      color: Colors.grey[50],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Replying to @$replyToUsername',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                replyToCommentId = null;
                                replyToUsername = null;
                                // Optional: clear the textfield if they cancel the reply and it was just the username
                                if (textController.text.trim().startsWith(
                                  '@',
                                )) {
                                  textController.clear();
                                }
                              });
                            },
                            child: const Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[200]!),
                      ),
                    ),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: ['❤️', '🔥', '😂', '👏', '😍', '😢', '🙌', '😮']
                          .map((emoji) {
                            return InkWell(
                              onTap: () {
                                final text = textController.text;
                                final selection = textController.selection;
                                String newText;
                                if (selection.isValid) {
                                  newText = text.replaceRange(
                                    selection.start,
                                    selection.end,
                                    emoji,
                                  );
                                } else {
                                  newText = text + emoji;
                                }
                                textController.text = newText;
                                textController.selection =
                                    TextSelection.fromPosition(
                                      TextPosition(offset: newText.length),
                                    );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 18),
                                ),
                              ),
                            );
                          })
                          .toList(),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundImage: currentUser.photoUrl != null
                                ? CachedNetworkImageProvider(
                                    currentUser.photoUrl!,
                                  )
                                : null,
                            child: currentUser.photoUrl == null
                                ? Text(
                                    currentUser.displayName.isNotEmpty
                                        ? currentUser.displayName[0]
                                              .toUpperCase()
                                        : '?',
                                    style: const TextStyle(fontSize: 10),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: textController,
                              focusNode: focusNode,
                              maxLines: null,
                              decoration: const InputDecoration(
                                hintText: 'Add a comment...',
                                hintStyle: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final text = textController.text.trim();
                              if (text.isEmpty) return;

                              final commentData = {
                                'uid': currentUser.uid,
                                'displayName': currentUser.displayName,
                                'photoUrl': currentUser.photoUrl,
                                'text': text,
                                'timestamp': FieldValue.serverTimestamp(),
                                'parentId': replyToCommentId,
                              };

                              textController.clear();
                              setState(() {
                                replyToCommentId = null;
                                replyToUsername = null;
                              });
                              focusNode.unfocus();

                              try {
                                await postDoc.reference
                                    .collection('comments')
                                    .add(commentData);
                              } catch (e) {
                                if (context.mounted) {
                                  TopNotificationService.showError(
                                    context,
                                    'Failed to add comment: $e',
                                  );
                                }
                              }
                            },
                            child: const Text(
                              'Post',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      textController.dispose();
      focusNode.dispose();
    });
  }

  void _showCommentOptions(
    BuildContext context,
    DocumentSnapshot commentDoc,
    String currentUserUid,
    String? postAuthorUid,
  ) {
    final data = commentDoc.data() as Map<String, dynamic>? ?? {};
    final commentAuthorUid = data['uid'] as String?;

    final canDelete =
        (currentUserUid == commentAuthorUid) ||
        (currentUserUid == postAuthorUid);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (canDelete)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                  ),
                  title: const Text(
                    'Delete Comment',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    commentDoc.reference.delete();
                    Navigator.pop(context);
                  },
                ),
              if (!canDelete) ...[
                ListTile(
                  leading: const Icon(
                    Icons.report_gmailerrorred_rounded,
                    color: Colors.red,
                  ),
                  title: const Text(
                    'Report',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    TopNotificationService.showSuccess(
                      context,
                      'Comment reported',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block_rounded),
                  title: const Text('Block'),
                  onTap: () {
                    Navigator.pop(context);
                    TopNotificationService.showSuccess(context, 'User blocked');
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommentItem({
    required DocumentSnapshot commentDoc,
    required bool isReply,
    required bool isLiked,
    required int likeCount,
    required VoidCallback onReplyTap,
    required VoidCallback onLikeTap,
    required VoidCallback onLongPress,
  }) {
    final data = commentDoc.data() as Map<String, dynamic>? ?? {};
    final String displayName = data['displayName'] ?? 'Anonymous';
    final String? photoUrl = data['photoUrl'];
    final String text = data['text'] ?? '';
    final int timestampMillis = parseTimestamp(data['timestamp']);
    final DateTime? timestampDate = timestampMillis > 0
        ? DateTime.fromMillisecondsSinceEpoch(timestampMillis)
        : null;

    String timeAgo = 'Just now';
    if (timestampDate != null) {
      final diff = DateTime.now().difference(timestampDate);
      if (diff.inMinutes < 1) {
        timeAgo = 'Just now';
      } else if (diff.inMinutes < 60) {
        timeAgo = '${diff.inMinutes}m';
      } else if (diff.inHours < 24) {
        timeAgo = '${diff.inHours}h';
      } else {
        timeAgo = '${diff.inDays}d';
      }
    }

    final RegExp mentionRegex = RegExp(r'^(@[\w\.]+)\s');
    final Match? match = mentionRegex.firstMatch(text);

    return GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: isReply ? 12 : 14,
              backgroundImage: photoUrl != null
                  ? CachedNetworkImageProvider(photoUrl)
                  : null,
              child: photoUrl == null
                  ? Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(fontSize: isReply ? 8 : 10),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                      ),
                      children: [
                        TextSpan(
                          text: '$displayName ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (match != null) ...[
                          TextSpan(
                            text: match.group(1)! + ' ',
                            style: const TextStyle(color: Colors.blue),
                          ),
                          TextSpan(text: text.substring(match.end)),
                        ] else ...[
                          TextSpan(text: text),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        timeAgo,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: onReplyTap,
                        child: const Text(
                          'Reply',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                GestureDetector(
                  onTap: onLikeTap,
                  child: Icon(
                    isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 14,
                    color: isLiked ? Colors.red : AppColors.textSecondary,
                  ),
                ),
                if (likeCount > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$likeCount',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getActiveReelsData() {
    final List<Map<String, dynamic>> reels = [];
    for (var doc in _reelsDocs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      reels.add({
        'doc': doc,
        'videoUrl': data['videoUrl'] ?? '',
        'thumbnail': data['thumbnail'] ?? '',
        'caption': data['caption'] ?? '',
        'creatorName':
            data['displayName'] ?? data['creatorName'] ?? 'Anonymous',
        'creatorAvatar': data['photoUrl'] ?? data['creatorAvatar'] ?? '',
      });
    }
    if (reels.isEmpty && !_isLoadingReels) {
      reels.addAll([
        {
          'videoUrl':
              'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
          'thumbnail': '',
          'caption':
              'Bees working hard! Nature is beautiful. #nature #bees #macro',
          'creatorName': '@nature_observer',
          'creatorAvatar': '',
        },
        {
          'videoUrl':
              'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
          'thumbnail': '',
          'caption':
              'Elegant butterfly taking off! #butterfly #garden #insects',
          'creatorName': '@macro_shots',
          'creatorAvatar': '',
        },
        {
          'videoUrl':
              'https://raw.githubusercontent.com/flutter/assets-for-api-docs/master/assets/videos/bee.mp4',
          'caption': 'High quality bee macro video close-up. #bees #explore',
          'creatorName': '@bee_keeper',
          'creatorAvatar': '',
          'thumbnail': '',
        },
        {
          'videoUrl':
              'https://raw.githubusercontent.com/flutter/assets-for-api-docs/master/assets/videos/butterfly.mp4',
          'caption': 'Butterfly flying around flowers. #spring #flowers',
          'creatorName': '@spring_life',
          'creatorAvatar': '',
          'thumbnail': '',
        },
      ]);
    }
    return reels;
  }

  Widget _buildReelsTab(UserModel currentUser) {
    return ReelsTab(
      currentUser: currentUser,
      reels: _getActiveReelsData(),
      isLoadingReels: _isLoadingReels,
      hasMoreReels: _hasMoreReels,
      pageController: _reelsPageController,
      controllers: _reelsControllers,
      activeReelIndex: _activeReelIndex,
      onPageChanged: (index) {
        final prev = _reelsControllers[_activeReelIndex];
        if (prev != null && prev.value.isInitialized && prev.value.isPlaying) {
          prev.pause();
        }
        setState(() {
          _activeReelIndex = index;
        });
        _manageReelsControllers();
        if (index >= _getActiveReelsData().length - 2) {
          _fetchReelsPage();
        }
      },
      onShowComments: (doc) => _showCommentsBottomSheet(context, doc, currentUser),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    UserModel currentUser,
    int tabIndex,
  ) {
    if (tabIndex == 0) {
      return StoryHeader(
        currentUser: currentUser,
        onStoryTap: (stories) => _showStoryViewer(context, stories),
        onAddStoryTap: () => _showCreateStoryDialog(context, currentUser),
      );
    }

    String title = 'Messages';
    String subtitle = 'Connect with friends';

    if (tabIndex == 3) {
      title = 'My Profile';
      subtitle = 'Manage details';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _buildNotificationBadge(ref, currentUser.uid),
              if (tabIndex == 3)
                Padding(
                  padding: const EdgeInsets.only(left: 12.0),
                  child: IconButton(
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: AppColors.textPrimary,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleCreatePostTap(BuildContext context, UserModel currentUser) async {
    final hasPermission = await _checkAndRequestPermission(
      Platform.isAndroid ? Permission.videos : Permission.photos,
    );

    if (hasPermission) {
      final resultMap = await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              const CustomGalleryPickerScreen(requestType: RequestType.common),
        ),
      );

      if (resultMap != null && resultMap['file'] is File && context.mounted) {
        final file = resultMap['file'] as File;
        final type = resultMap['type'] as String;

        if (type == 'image') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ImageEditorScreen(
                imageFile: file,
                currentUser: currentUser,
                mode: 'post',
                initialCaption: '',
                onSuccess: () {
                  _fetchFeedPostsPage(isRefresh: true);
                  ref.read(mediaRefreshProvider.notifier).state++;
                },
              ),
            ),
          );
        } else if (type == 'video') {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => ReelUploadScreen(
                videoFile: file,
                currentUser: currentUser,
                mode: 'post', // Upload as video post
              ),
            ),
          );
          if (result == true && context.mounted) {
            _fetchFeedPostsPage(isRefresh: true);
            ref.read(mediaRefreshProvider.notifier).state++;
          }
        }
      }
    }
  }

  Future<bool> _checkAndRequestPermission(Permission permission) async {
    final status = await permission.request();
    if (status.isGranted || status.isLimited) {
      return true;
    }
    if (Platform.isAndroid &&
        (permission == Permission.photos || permission == Permission.videos)) {
      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    }
    return false;
  }

  void _showCreateReelDialog(
    BuildContext context,
    UserModel currentUser,
  ) async {
    final hasPermission = await _checkAndRequestPermission(
      Platform.isAndroid ? Permission.videos : Permission.photos,
    );

    if (hasPermission) {
      final resultMap = await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              const CustomGalleryPickerScreen(requestType: RequestType.video),
        ),
      );

      if (resultMap != null && resultMap['file'] is File && context.mounted) {
        final videoFile = resultMap['file'] as File;
        _pauseActiveReel();
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => ReelUploadScreen(
              videoFile: videoFile,
              currentUser: currentUser,
              mode: 'reel',
            ),
          ),
        );
        try {
          if (result == true && context.mounted) {
            ref.read(mediaRefreshProvider.notifier).state++;
          }
          _resumeActiveReel();
        } catch (e) {
          debugPrint("Failed to handle reel upload result: $e");
          _resumeActiveReel();
        }
      }
    } else {
      if (context.mounted) {
        TopNotificationService.showError(
          context,
          'Video permission is required to upload reels.',
        );
      }
    }
  }

  void _showCreateStoryDialog(
    BuildContext context,
    UserModel currentUser,
  ) async {
    final hasPermission = await _checkAndRequestPermission(
      Platform.isAndroid ? Permission.videos : Permission.photos,
    );

    if (hasPermission) {
      final resultMap = await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              const CustomGalleryPickerScreen(requestType: RequestType.common),
        ),
      );

      if (resultMap != null && resultMap['file'] is File && context.mounted) {
        final file = resultMap['file'] as File;
        final type = resultMap['type'] as String;

        _pauseActiveReel();
        if (type == 'image') {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ImageEditorScreen(
                imageFile: file,
                currentUser: currentUser,
                mode: 'story',
              ),
            ),
          );
        } else if (type == 'video') {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReelUploadScreen(
                videoFile: file,
                currentUser: currentUser,
                mode: 'story',
              ),
            ),
          );
        }
        _resumeActiveReel();
      }
    } else {
      if (context.mounted) {
        TopNotificationService.showError(
          context,
          'Permissions are required to post stories.',
        );
      }
    }
  }

  void _showStoryViewer(
    BuildContext context,
    List<Map<String, dynamic>> stories,
  ) {
    if (stories.isEmpty) return;
    ref.read(isStoryDialogOpenProvider.notifier).state = true;
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) {
        return StoryViewerDialog(stories: stories);
      },
    ).then((_) {
      if (mounted) ref.read(isStoryDialogOpenProvider.notifier).state = false;
    });
  }

  Widget _buildHeaderAction(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
            ),
          ],
        ),
        child: Icon(icon, color: AppColors.primary, size: 22),
      ),
    );
  }

  Widget _buildNotificationBadge(WidgetRef ref, String uid) {
    final unreadCountAsync = ref.watch(unreadNotificationsCountProvider(uid));
    return unreadCountAsync.when(
      data: (notifCount) => Stack(
        clipBehavior: Clip.none,
        children: [
          _buildHeaderAction(Icons.notifications_none, () {
            _pauseActiveReel();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            );
          }),
          if (notifCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  notifCount > 9 ? '9+' : '$notifCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      loading: () => _buildHeaderAction(Icons.notifications_none, () {}),
      error: (_, err) => _buildHeaderAction(Icons.notifications_none, () {}),
    );
  }

  Widget _buildUserTile(UserModel user, UserModel currentUser, DateTime now) {
    final isActuallyOnline =
        user.isOnline && now.difference(user.lastSeen!).inMinutes < 2;
    final isFollowing = currentUser.following.contains(user.uid);
    final followBack = user.following.contains(currentUser.uid);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        onTap: () {
          _pauseActiveReel();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => UserProfileScreen(user: user)),
          );
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Stack(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                ),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: user.photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: user.photoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: Colors.black12),
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.error),
                      )
                    : Center(
                        child: Text(
                          user.displayName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
              ),
            ),
            if (isActuallyOnline)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          user.displayName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Row(
          children: [
            Text(
              isActuallyOnline
                  ? 'Online now'
                  : _formatLastSeen(user.lastSeen, now),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            if (isFollowing && followBack) ...[
              const SizedBox(width: 8),
              const Icon(Icons.verified, color: AppColors.primary, size: 14),
            ] else if (isFollowing) ...[
              const SizedBox(width: 8),
              const Text(
                '• Following',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: Colors.black12,
          size: 20,
        ),
      ),
    );
  }

  String _formatLastSeen(DateTime? lastSeen, DateTime now) {
    if (lastSeen == null) return 'Never';
    final difference = now.difference(lastSeen);
    if (difference.inMinutes < 60) return 'Active ${difference.inMinutes}m ago';
    if (difference.inHours < 24) return 'Active ${difference.inHours}h ago';
    return 'Active ${difference.inDays}d ago';
  }
}

// ----------------------------------------------------------------------
// Reels Video Player Item Widget
// ----------------------------------------------------------------------
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
            child: const Text(
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
                        CircleAvatar(
                          radius: 18,
                          backgroundImage:
                              photoUrl != null && photoUrl.isNotEmpty
                              ? CachedNetworkImageProvider(photoUrl)
                              : null,
                          child: (photoUrl == null || photoUrl.isEmpty)
                              ? Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : '?',
                                )
                              : null,
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

final isStoryDialogOpenProvider = StateProvider<bool>((ref) => false);

final currentTabIndexProvider = StateProvider<int>((ref) => 0);

final activeFeedVideoProvider = Provider<String?>((ref) {
  // (Removed currentTabIndexProvider check so videos can play in UserPostsScreen)

  final visibilities = ref.watch(feedVideoVisibilityProvider);
  if (visibilities.isEmpty) {
    return null;
  }

  String? mostVisible;
  double maxVis = 0.0;

  for (var entry in visibilities.entries) {
    if (entry.value > maxVis) {
      maxVis = entry.value;
      mostVisible = entry.key;
    }
  }

  if (maxVis >= 0.15) {
    return mostVisible;
  }
  return null;
});

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
        // We use networkUrl to stream the video immediately instead of hanging the thread waiting for a full file download via getSingleFile.
      }
      await controller.initialize();
      if (mounted && !_isDisposed && _isInitializing) {
        setState(() {
          _controller = controller;
          _isInitialized = true;
          _isInitializing = false;
          _lastKnownAspectRatio = controller.value.aspectRatio;
        });
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
      if (!controller.value.isPlaying) {
        controller.play();
        controller.setLooping(true);
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

  void _disposeController() {
    if (_isDisposed) return;
    final controller = _controller;
    _controller = null;
    _isInitialized = false;
    _isInitializing = false;
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
                child: CircularProgressIndicator(color: Colors.white),
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
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                    errorWidget: (context, url, error) => const AspectRatio(
                      aspectRatio: 4 / 5,
                      child: SizedBox.shrink(),
                    ),
                  ),
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ],
              )
            : const AspectRatio(
                aspectRatio: 4 / 5,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
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

            // Single tap handler to open full screen
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          FullScreenFeedVideoScreen(videoUrl: widget.videoUrl),
                    ),
                  );
                },
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(),
              ),
            ),

            // ── Global Feed Mute Button (bottom-right) ──────────────────────
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

  @override
  void initState() {
    super.initState();
    _initVideo();
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
      final isMuted = ref.read(feedMuteProvider);
      _controller!.setVolume(isMuted ? 0 : 1);
      _controller!.setLooping(true);
      _controller!.play();
    } catch (e) {
      debugPrint('Failed to load full screen video: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
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
                        if (!_controller!.value.isPlaying)
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
                      ],
                    ),
                  )
                : const Center(
                    child: RepaintBoundary(
                      child: CircularProgressIndicator(color: Colors.white),
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
          if (_isInitialized)
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
          if (uid != currentUser.uid && !currentUser.following.contains(uid))
            continue;
          if (!grouped.containsKey(uid)) grouped[uid] = [];
          grouped[uid]!.add({'id': doc.id, ...data});
        }

        final myStories = grouped[currentUser.uid] ?? [];
        final otherUsersUids = _buildSortedUids(grouped, currentUser.uid);

        return Container(
          height: 110,
          padding: const EdgeInsets.only(
            top: 14.0,
            bottom: 6.0,
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
                                      child: CircleAvatar(
                                        radius: 22,
                                        backgroundImage:
                                            currentUser.photoUrl != null &&
                                                currentUser.photoUrl!.isNotEmpty
                                            ? CachedNetworkImageProvider(
                                                currentUser.photoUrl!,
                                              )
                                            : null,
                                        child:
                                            (currentUser.photoUrl == null ||
                                                currentUser.photoUrl!.isEmpty)
                                            ? Text(
                                                currentUser
                                                        .displayName
                                                        .isNotEmpty
                                                    ? currentUser.displayName[0]
                                                          .toUpperCase()
                                                    : '?',
                                              )
                                            : null,
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
                                child: CircleAvatar(
                                  radius: 22,
                                  backgroundImage:
                                      photoUrl != null && photoUrl.isNotEmpty
                                      ? CachedNetworkImageProvider(photoUrl)
                                      : null,
                                  child: (photoUrl == null || photoUrl.isEmpty)
                                      ? Text(
                                          displayName.isNotEmpty
                                              ? displayName[0].toUpperCase()
                                              : '?',
                                        )
                                      : null,
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
