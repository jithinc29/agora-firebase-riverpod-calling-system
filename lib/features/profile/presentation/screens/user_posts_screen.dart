import 'package:call_project/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/home/presentation/widgets/feed_post_card.dart';
import 'package:call_project/features/profile/controllers/user_posts_controller.dart';

class UserPostsScreen extends ConsumerStatefulWidget {
  final UserModel currentUser;
  final String targetUserId;
  final int initialIndex;
  final List<DocumentSnapshot> posts;

  const UserPostsScreen({
    super.key,
    required this.currentUser,
    required this.targetUserId,
    required this.initialIndex,
    required this.posts,
  });

  @override
  ConsumerState<UserPostsScreen> createState() => _UserPostsScreenState();
}

class _UserPostsScreenState extends ConsumerState<UserPostsScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(userPostsProvider.notifier)
          .init(widget.posts, widget.initialIndex);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Posts',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final posts = ref.watch(userPostsProvider);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }

    if (posts.isEmpty) {
      return const Center(child: Text('No posts found.'));
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: posts.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final doc = posts[index];
        return FeedPostCard(
          key: ValueKey(doc.id),
          postDoc: doc,
          currentUser: widget.currentUser,
          onPostDeleted: () {
            ref.read(userPostsProvider.notifier).removePost(doc.id);
          },
          onPostHidden: () {
            ref.read(userPostsProvider.notifier).removePost(doc.id);
          },
        );
      },
    );
  }
}
