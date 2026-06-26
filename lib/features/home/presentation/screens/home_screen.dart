import 'dart:async';
import 'package:call_project/features/home/presentation/tabs/reels_tab.dart';
import 'package:call_project/features/home/presentation/tabs/chats_tab.dart';
import 'package:call_project/features/home/presentation/tabs/feed_tab.dart';
import 'package:call_project/features/home/presentation/widgets/post_creator_card.dart';
import 'package:call_project/features/home/presentation/widgets/feed_post_card.dart';
import 'package:call_project/features/home/presentation/providers/home_providers.dart';
import 'package:call_project/features/home/presentation/widgets/story_viewer_dialog.dart';
import 'package:call_project/features/home/presentation/utils/comments_bottom_sheet_helper.dart';
import 'package:call_project/core/utils/time_utils.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:call_project/features/auth/repository/auth_repository.dart';
import 'package:call_project/features/users/data/repository/user_repository.dart';
import 'package:call_project/features/profile/presentation/screens/profile_screen.dart';
import 'package:call_project/features/notifications/presentation/screens/notification_screen.dart';
import 'package:call_project/features/notifications/data/repository/notification_repository.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/home/presentation/widgets/custom_bottom_nav_bar.dart';
import 'package:call_project/core/services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:call_project/features/home/presentation/screens/image_editor_screen.dart';
import 'package:call_project/features/home/presentation/screens/reel_upload_screen.dart';
import 'package:call_project/core/providers/refresh_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
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
      formatLastSeen: formatLastSeen,
    );
  }

  Widget _buildFeedsTab(UserModel currentUser) {
    return FeedTab(
      onRefresh: () => _fetchFeedPostsPage(isRefresh: true),
      postCreatorCard: PostCreatorCard(
        currentUser: currentUser,
        onPostCreated: () {
          _fetchFeedPostsPage(isRefresh: true);
          ref.read(mediaRefreshProvider.notifier).state++;
        },
      ),
      isLoading: _isLoadingFeedPosts,
      hasMore: _hasMoreFeedPosts,
      isEmpty: _feedPosts.isEmpty,
      scrollController: _feedScrollController,
      itemCount:
          _feedPosts.length +
          (_isLoadingFeedPosts ? 1 : 0) +
          (_isShowingSuggestedFeed ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isShowingSuggestedFeed && index == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

        final actualIndex = _isShowingSuggestedFeed ? index - 1 : index;

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
        return FeedPostCard(
          postDoc: doc,
          currentUser: currentUser,
          onPostDeleted: () {
            _fetchFeedPostsPage(isRefresh: true);
            ref.read(mediaRefreshProvider.notifier).state++;
          },
          onPostHidden: () {
            setState(() {
              _hiddenPostIds.add(doc.id);
            });
          },
        );
      },
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
      onShowComments: (doc) =>
          CommentsBottomSheetHelper.show(context, doc, currentUser),
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
}
