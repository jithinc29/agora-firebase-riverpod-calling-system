import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/auth/repository/auth_repository.dart';
import 'package:call_project/features/auth/controllers/auth_controller.dart';
import 'package:call_project/features/users/data/repository/user_repository.dart';
import 'package:call_project/core/providers/firebase_providers.dart';
import 'package:call_project/core/services/notification_service.dart';
import 'package:call_project/features/users/presentation/screens/follow_list_screen.dart';
import 'package:call_project/features/users/presentation/screens/block_list_screen.dart';

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

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isUploading = false;
  bool _isSaving = false;

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

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 400,
    );

    if (image == null) return;

    setState(() => _isUploading = true);

    try {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null) return;

      final storageRef = ref.read(storageProvider).ref().child('profile_pics/${user.uid}.jpg');
      await storageRef.putFile(File(image.path));
      final downloadUrl = await storageRef.getDownloadURL();

      await ref.read(userRepositoryProvider).updateUserProfile(user.uid, {
        'photoUrl': downloadUrl,
      });

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

      await ref.read(userRepositoryProvider).updateUserProfile(user.uid, {
        'displayName': _nameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
      });

      if (mounted) {
        TopNotificationService.showSuccess(context, 'Profile updated successfully!');
      }
    } catch (e) {
      if (mounted) {
        TopNotificationService.showError(context, 'Failed to update profile: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _signOut() {
    ref.read(authControllerProvider.notifier).signOut();
    Navigator.of(context).pop();
  }

  void _showDeleteConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete Account?'),
        content: const Text('This will permanently delete your account and profile data. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserDataProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: userAsync.when(
        data: (user) {
          if (user == null) return const Center(child: Text('User not found'));
          return Stack(
            children: [
              // Fixed Curved Header
              _buildCurvedHeader(context),

              // Scrollable Content
              SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 100),
                    _buildProfileHeader(user),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          _buildStatsRow(context, user),
                          const SizedBox(height: 24),
                          _buildFollowRequests(user),
                          const SizedBox(height: 24),
                          _buildProfileSection(user),
                          const SizedBox(height: 24),
                          _buildSettingsSection(),
                          const SizedBox(height: 32),
                          _buildSaveButton(),
                          const SizedBox(height: 16),
                          _buildLogoutButton(),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ],
                ),
              ),


              // Back Button (Fixed Top Left)
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 16,
                child: CircleAvatar(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildCurvedHeader(BuildContext context) {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.secondary],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(50),
          bottomRight: Radius.circular(50),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(UserModel user) {
    return Column(
      children: [
        Stack(
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10)),
                ],
                image: user.photoUrl != null
                    ? DecorationImage(image: NetworkImage(user.photoUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: user.photoUrl == null
                  ? Container(
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: Center(
                        child: Text(
                          user.displayName[0].toUpperCase(),
                          style: const TextStyle(fontSize: 48, color: AppColors.primary, fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: _isUploading ? null : _pickAndUploadImage,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
                  child: Icon(_isUploading ? Icons.sync : Icons.camera_alt_rounded, color: AppColors.primary, size: 20),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          user.displayName,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Active now',
              style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context, UserModel user) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(context, 'Followers', user.followers.length, user.followers),
          Container(width: 1, height: 30, color: Colors.grey.withValues(alpha: 0.1)),
          _buildStatItem(context, 'Following', user.following.length, user.following),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, int count, List<String> uids) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FollowListScreen(title: label, uids: uids))),
      child: Column(
        children: [
          Text(count.toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildFollowRequests(UserModel user) {
    if (user.pendingFollowRequests.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text('FOLLOW REQUESTS', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
        ),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: user.pendingFollowRequests.length,
            itemBuilder: (context, index) {
              final uid = user.pendingFollowRequests[index];
              final requesterAsync = ref.watch(userDetailsProvider(uid));
              return requesterAsync.when(
                data: (requester) => requester == null ? const SizedBox.shrink() : ListTile(
                  leading: CircleAvatar(backgroundImage: requester.photoUrl != null ? NetworkImage(requester.photoUrl!) : null),
                  title: Text(requester.displayName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.check_circle_rounded, color: AppColors.success), onPressed: () => ref.read(userRepositoryProvider).acceptFollowRequest(user.uid, uid)),
                      IconButton(icon: const Icon(Icons.cancel_rounded, color: AppColors.error), onPressed: () {
                        ref.read(userRepositoryProvider).updateUserProfile(user.uid, {'pendingFollowRequests': FieldValue.arrayRemove([uid])});
                      }),
                    ],
                  ),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProfileSection(UserModel user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text('PROFILE DETAILS', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            children: [
              _buildField('Display Name', _nameController, Icons.person_outline_rounded),
              const SizedBox(height: 24),
              _buildField('Phone Number', _phoneController, Icons.phone_outlined, keyboardType: TextInputType.phone),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildField(String label, TextEditingController controller, IconData icon, {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            icon: Icon(icon, color: AppColors.primary, size: 22),
            border: InputBorder.none,
            hintText: 'Enter $label',
            hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.4), fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text('PREFERENCES', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
        ),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            children: [
              _buildSettingTile('Blocked Users', Icons.block_rounded, AppColors.primary, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockListScreen()))),
              _buildSettingTile('Delete Account', Icons.delete_forever_rounded, AppColors.error, _showDeleteConfirmation),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingTile(String title, IconData icon, Color color, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.black12),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 8,
          shadowColor: AppColors.primary.withValues(alpha: 0.3),
        ),
        child: _isSaving
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: OutlinedButton.icon(
        onPressed: _signOut,
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Logout Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }
}
