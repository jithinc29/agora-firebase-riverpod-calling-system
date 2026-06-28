import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:call_project/features/home/presentation/widgets/reels_player_item.dart';
import 'package:video_player/video_player.dart';
import 'package:call_project/features/auth/models/user_model.dart';

class ReelsTab extends StatelessWidget {
  final UserModel currentUser;
  final List<Map<String, dynamic>> reels;
  final bool isLoadingReels;
  final bool hasMoreReels;
  final PageController pageController;
  final Map<int, VideoPlayerController> controllers;
  final int activeReelIndex;
  final Function(int) onPageChanged;
  final Function(DocumentSnapshot) onShowComments;

  const ReelsTab({
    super.key,
    required this.currentUser,
    required this.reels,
    required this.isLoadingReels,
    required this.hasMoreReels,
    required this.pageController,
    required this.controllers,
    required this.activeReelIndex,
    required this.onPageChanged,
    required this.onShowComments,
  });

  @override
  Widget build(BuildContext context) {
    if (reels.isEmpty && (isLoadingReels || hasMoreReels)) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: SizedBox.shrink()),
      );
    }

    if (reels.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.video_library, color: Colors.white54, size: 48),
              SizedBox(height: 16),
              Text(
                "No reels found",
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              SizedBox(height: 8),
              Text(
                "Swipe down to refresh",
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: pageController,
        scrollDirection: Axis.vertical,
        physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
        itemCount: reels.length,
        onPageChanged: onPageChanged,
        itemBuilder: (context, index) {
          final reel = reels[index];
          final controller = controllers[index];
          return RepaintBoundary(
            child: ReelsPlayerItem(
              key: ValueKey('reel_$index'),
              reelDoc: reel['doc'],
              currentUser: currentUser,
              videoUrl: reel['videoUrl']!,
              thumbnailUrl: reel['thumbnail'],
              caption: reel['caption']!,
              creatorName: reel['creatorName']!,
              creatorAvatar: reel['creatorAvatar'],
              isActive: index == activeReelIndex,
              controller: controller,
              onCommentTap: reel['doc'] != null
                  ? () => onShowComments(reel['doc'])
                  : null,
            ),
          );
        },
      ),
    );
  }
}
