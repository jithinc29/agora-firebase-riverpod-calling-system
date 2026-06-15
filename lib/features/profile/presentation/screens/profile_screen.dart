import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/profile/presentation/screens/user_posts_screen.dart';
import 'package:call_project/core/providers/refresh_provider.dart';
import 'package:call_project/features/auth/repository/auth_repository.dart';
import 'package:call_project/features/auth/controllers/auth_controller.dart';
import 'package:call_project/features/users/data/repository/user_repository.dart';
import 'package:call_project/core/providers/firebase_providers.dart';
import 'package:call_project/core/services/notification_service.dart';
import 'package:call_project/features/users/presentation/screens/follow_list_screen.dart';
import 'package:call_project/features/users/presentation/screens/block_list_screen.dart';
import 'package:call_project/features/profile/presentation/screens/follow_requests_screen.dart';
import 'package:call_project/features/profile/presentation/screens/settings_screen.dart';

class AppColors {
  static const primary = Color(0xFF6366F1); // Indigo
  static const secondary = Color(0xFFA855F7); // Purple
  static const background = Color(0xFFF8FAFC); // Slate Light
  static const success = Color(0xFF10B981); // Emerald
  static const error = Color(0xFFEF4444); // Rose
  static const textPrimary = Color(0xFF0F172A); // Midnight
  static const textSecondary = Color(0xFF64748B); // Slate Muted
}

class ProfileScreen extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const ProfileScreen({super.key, this.isEmbedded = false});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isUploading = false;
  bool _isSaving = false;
  File? _localSelectedImage;
  Future<List<Map<String, dynamic>>>? _mediaFuture;
  String? _lastUid;
  List<DocumentSnapshot> _postsDocs = [];

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserDataProvider).asData?.value;
    if (user != null) {
      _nameController.text = user.displayName;
      _phoneController.text = user.phoneNumber ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<bool> _checkAndRequestPermission(Permission permission) async {
    final status = await permission.request();
    if (status.isGranted || status.isLimited) return true;
    if (Platform.isAndroid && (permission == Permission.photos || permission == Permission.videos)) {
      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    }
    return false;
  }

  Future<void> _pickAndUploadImage() async {
    final hasPermission = await _checkAndRequestPermission(Permission.photos);
    if (!hasPermission) {
      if (mounted) {
        TopNotificationService.showError(context, 'Photo permission is required.');
      }
      return;
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 400,
    );

    if (image == null) return;

    setState(() {
      _localSelectedImage = File(image.path);
      _isUploading = true;
    });

    try {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null) return;

      final storageRef = ref
          .read(storageProvider)
          .ref()
          .child('profile_pics/${user.uid}.jpg');
      await storageRef.putFile(File(image.path));
      final downloadUrl = await storageRef.getDownloadURL();

      await ref.read(userRepositoryProvider).updateUserProfile(user.uid, {
        'photoUrl': downloadUrl,
      });

      // Update denormalized photoUrl in all posts, reels, stories, and comments
      await _updateDenormalizedUserData(user.uid, newPhotoUrl: downloadUrl);

      if (mounted) {
        TopNotificationService.showSuccess(context, 'Profile picture updated!');
      }
    } catch (e) {
      if (mounted) {
        TopNotificationService.showError(context, 'Failed to upload image: $e');
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null) return;

      final newName = _nameController.text.trim();
      await ref.read(userRepositoryProvider).updateUserProfile(user.uid, {
        'displayName': newName,
        'phoneNumber': _phoneController.text.trim(),
      });

      // Update denormalized displayName in all posts, reels, stories, and comments
      await _updateDenormalizedUserData(user.uid, newName: newName);

      if (mounted) {
        TopNotificationService.showSuccess(
          context,
          'Profile updated successfully!',
        );
      }
    } catch (e) {
      if (mounted) {
        TopNotificationService.showError(
          context,
          'Failed to update profile: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _updateDenormalizedUserData(String uid, {String? newName, String? newPhotoUrl}) async {
    if (newName == null && newPhotoUrl == null) return;

    final updates = <String, dynamic>{};
    if (newName != null) updates['displayName'] = newName;
    if (newPhotoUrl != null) updates['photoUrl'] = newPhotoUrl;

    try {
      final batch = FirebaseFirestore.instance.batch();

      // 1. Posts
      final posts = await FirebaseFirestore.instance.collection('posts').where('uid', isEqualTo: uid).get();
      for (var doc in posts.docs) {
        batch.update(doc.reference, updates);
      }

      // 2. Reels
      final reels = await FirebaseFirestore.instance.collection('reels').where('uid', isEqualTo: uid).get();
      for (var doc in reels.docs) {
        batch.update(doc.reference, updates);
      }

      // 3. Stories
      final stories = await FirebaseFirestore.instance.collection('stories').where('uid', isEqualTo: uid).get();
      for (var doc in stories.docs) {
        batch.update(doc.reference, updates);
      }

      // 4. Comments (using collectionGroup to find all comments by this user across all posts/reels)
      final comments = await FirebaseFirestore.instance.collectionGroup('comments').where('uid', isEqualTo: uid).get();
      for (var doc in comments.docs) {
        batch.update(doc.reference, updates);
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error updating denormalized user data: $e');
    }
  }
  void _signOut() {
    ref.read(authControllerProvider.notifier).signOut();
    if (!widget.isEmbedded) {
      Navigator.of(context).pop();
    }
  }

  void _showDeleteConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete Account?'),
        content: const Text(
          'This will permanently delete your account and profile data. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
        
        try {
          await ref.read(authControllerProvider.notifier).deleteAccount();
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        } catch (e) {
          if (mounted) {
            Navigator.pop(context); // Dismiss loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to delete account: $e')),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(mediaRefreshProvider, (previous, next) {
      final user = ref.read(currentUserDataProvider).asData?.value;
      if (user != null) {
        setState(() {
          _mediaFuture = _fetchUserMedia(user.uid);
        });
      }
    });

    final userAsync = ref.watch(currentUserDataProvider);
    final allUsersAsync = ref.watch(allUsersProvider);

    final content = userAsync.when(
      data: (user) {
        if (user == null) return const Center(child: Text('User not found'));

        return allUsersAsync.when(
          data: (allUsers) {
            final registeredUids = allUsers.map((u) => u.uid).toSet();

            final activeFollowers = user.followers
                .where((uid) => registeredUids.contains(uid))
                .toList();
            final activeFollowing = user.following
                .where((uid) => registeredUids.contains(uid))
                .toList();
            final activePendingRequests = user.pendingFollowRequests
                .where((uid) => registeredUids.contains(uid))
                .toList();

            if (_mediaFuture == null || _lastUid != user.uid) {
              _lastUid = user.uid;
              _mediaFuture = _fetchUserMedia(user.uid);
            }

            return DefaultTabController(
              length: 2,
              child: RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    _mediaFuture = _fetchUserMedia(user.uid);
                  });
                  await _mediaFuture;
                },
                child: NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) {
                    return [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            children: [
                              _buildProfileHeaderCard(
                                user,
                                activeFollowers,
                                activeFollowing,
                                activePendingRequests,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _SliverAppBarDelegate(
                          const TabBar(
                            indicatorColor: AppColors.primary,
                            labelColor: AppColors.primary,
                            unselectedLabelColor: AppColors.textSecondary,
                            tabs: [
                              Tab(icon: Icon(Icons.grid_on_rounded)),
                              Tab(icon: Icon(Icons.ondemand_video_rounded)),
                            ],
                          ),
                        ),
                      ),
                    ];
                  },
                  body: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _mediaFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error: ${snapshot.error}',
                            style: TextStyle(color: Colors.red),
                          ),
                        );
                      }
                      final allMedia = snapshot.data ?? [];
                      final videosOnly = allMedia
                          .where((m) => m['type'] == 'video')
                          .toList();

                      return TabBarView(
                        children: [
                          _buildMediaGrid(allMedia, user, isVideosOnly: false),
                          _buildMediaGrid(videosOnly, user, isVideosOnly: true),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );

    if (widget.isEmbedded) {
      return Container(color: AppColors.background, child: content);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: content,
    );
  }

  Widget _buildProfileHeaderCard(
    UserModel user,
    List<String> activeFollowers,
    List<String> activeFollowing,
    List<String> activePendingRequests,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar Stack
              Stack(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: ClipOval(
                      child: _localSelectedImage != null
                          ? Image.file(
                              _localSelectedImage!,
                              fit: BoxFit.cover,
                              width: 72,
                              height: 72,
                            )
                          : user.photoUrl != null
                          ? CachedNetworkImage(
                              imageUrl: user.photoUrl!,
                              fit: BoxFit.cover,
                              width: 72,
                              height: 72,
                              fadeInDuration: const Duration(milliseconds: 100),
                              placeholder: (context, url) => Container(
                                color: AppColors.primary.withValues(alpha: 0.05),
                                child: Center(
                                  child: Text(
                                    user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                                    style: const TextStyle(fontSize: 26, color: AppColors.primary, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => const Icon(Icons.error, size: 20),
                            )
                          : Container(
                              color: AppColors.primary.withValues(alpha: 0.05),
                              child: Center(
                                child: Text(
                                  user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                                  style: const TextStyle(fontSize: 26, color: AppColors.primary, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn('Posts', '${_postsDocs.length}'),
                    _buildStatColumn(
                      'Followers', 
                      '${activeFollowers.length}',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FollowListScreen(title: 'Followers', uids: activeFollowers))),
                    ),
                    _buildStatColumn(
                      'Following', 
                      '${activeFollowing.length}',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FollowListScreen(title: 'Following', uids: activeFollowing))),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            user.displayName,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              const Text('Active now', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w500, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: () => _showEditProfileSheet(context, user),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                width: 36,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FollowRequestsScreen(
                          currentUserId: user.uid,
                          pendingRequests: activePendingRequests,
                        ),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.people_alt_outlined, size: 18),
                      if (activePendingRequests.isNotEmpty)
                        Positioned(
                          top: -2,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${activePendingRequests.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String count, {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Text(count, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      ),
    ),
  );
}



  void _showEditProfileSheet(BuildContext context, UserModel user) {
    _nameController.text = user.displayName;
    _phoneController.text = user.phoneNumber ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final viewInsets = MediaQuery.of(context).viewInsets;
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withValues(alpha: 0.1),
                            ),
                            child: ClipOval(
                              child: _localSelectedImage != null
                                  ? Image.file(_localSelectedImage!, fit: BoxFit.cover)
                                  : (user.photoUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: user.photoUrl!,
                                          fit: BoxFit.cover,
                                        )
                                      : Center(
                                          child: Text(
                                            user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                                            style: const TextStyle(fontSize: 32, color: AppColors.primary, fontWeight: FontWeight.bold),
                                          ),
                                        )),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _isUploading ? null : () async {
                                await _pickAndUploadImage();
                                setSheetState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: _isUploading 
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Edit Profile',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    _buildField(
                      'Display Name',
                      _nameController,
                      Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      'Phone Number',
                      _phoneController,
                      Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSaving
                            ? null
                            : () async {
                                setSheetState(() => _isSaving = true);
                                await _saveProfile();
                                setSheetState(() => _isSaving = false);
                                if (context.mounted) Navigator.pop(context);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon, {
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          decoration: InputDecoration(
            icon: Icon(icon, color: AppColors.primary, size: 16),
            border: InputBorder.none,
            hintText: 'Enter ',
            hintStyle: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.4),
              fontSize: 12,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _fetchUserMedia(String uid) async {
    final postsFuture = FirebaseFirestore.instance
        .collection('posts')
        .where('uid', isEqualTo: uid)
        .get();

    final reelsFuture = FirebaseFirestore.instance
        .collection('reels')
        .where('uid', isEqualTo: uid)
        .get();

    final results = await Future.wait([postsFuture, reelsFuture]);

    final postsDocs = results[0].docs.toList();
    postsDocs.sort((a, b) {
      final aTime =
          ((a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?)
              ?.millisecondsSinceEpoch ??
          0;
      final bTime =
          ((b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?)
              ?.millisecondsSinceEpoch ??
          0;
      return bTime.compareTo(aTime);
    });
    _postsDocs = postsDocs;

    final reelsDocs = results[1].docs;

    final List<Map<String, dynamic>> allMedia = [];

    for (var doc in postsDocs) {
      final data = doc.data();
      if (data['type'] == 'image' || data['type'] == 'video') {
        data['id'] = doc.id;
        data['doc'] = doc;
        data['source'] = 'post';
        allMedia.add(data);
      }
    }

    for (var doc in reelsDocs) {
      final data = doc.data();
      data['id'] = doc.id;
      data['doc'] = doc;
      data['source'] = 'reel';
      data['type'] = 'video';
      allMedia.add(data);
    }

    allMedia.sort((a, b) {
      final aTime = (a['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final bTime = (b['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });

    if (mounted) {
      setState(() {});
    }

    return allMedia;
  }

  Widget _buildMediaGrid(
    List<Map<String, dynamic>> mediaList,
    UserModel user, {
    bool isVideosOnly = false,
  }) {
    if (mediaList.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined, size: 48, color: Colors.black26),
            SizedBox(height: 16),
            Text(
              'No Posts Yet',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 1,
      ),
      itemCount: mediaList.length,
      itemBuilder: (context, index) {
        final media = mediaList[index];
        final isVideo = media['type'] == 'video';
        final thumbnailUrl = isVideo
            ? media['thumbnailUrl'] ?? media['thumbnail']
            : media['mediaUrl'];

        return GestureDetector(
          onTap: () {
            final media = mediaList[index];
            if (media['source'] == 'reel') {
              final docsToPass = mediaList.map((m) => m['doc'] as DocumentSnapshot).toList();
              int targetIndex = docsToPass.indexWhere((doc) => doc.id == media['id']);
              if (targetIndex == -1) targetIndex = 0;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserPostsScreen(
                    currentUser: user,
                    targetUserId: user.uid,
                    initialIndex: targetIndex,
                    posts: docsToPass,
                  ),
                ),
              );
              return;
            }

            final postsToPass = isVideosOnly
                ? _postsDocs
                      .where(
                        (p) =>
                            (p.data() as Map<String, dynamic>)['type'] ==
                            'video',
                      )
                      .toList()
                : _postsDocs;

            int targetIndex = postsToPass.indexWhere(
              (p) => p.id == media['id'],
            );
            if (targetIndex != -1) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserPostsScreen(
                    currentUser: user,
                    targetUserId: user.uid,
                    initialIndex: targetIndex,
                    posts: postsToPass,
                  ),
                ),
              );
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.grey.shade200),
              if (thumbnailUrl != null && thumbnailUrl.toString().isNotEmpty)
                CachedNetworkImage(
                  imageUrl: thumbnailUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              if (isVideo)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.play_circle_outline_rounded,
                    color: Colors.white,
                    size: 20,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: Colors.white, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
