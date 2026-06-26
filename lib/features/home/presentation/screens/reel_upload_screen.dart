import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/home/presentation/screens/home_screen.dart'; // For AppColors
import 'package:call_project/core/services/notification_service.dart';
import 'package:call_project/features/home/presentation/utils/video_compression_service.dart';
import 'package:video_compress/video_compress.dart';

class ReelUploadScreen extends StatefulWidget {
  final File videoFile;
  final UserModel currentUser;
  final String mode;

  const ReelUploadScreen({
    super.key,
    required this.videoFile,
    required this.currentUser,
    this.mode = 'reel',
  });

  @override
  State<ReelUploadScreen> createState() => _ReelUploadScreenState();
}

class _ReelUploadScreenState extends State<ReelUploadScreen> {
  late VideoPlayerController _videoController;
  final TextEditingController _captionController = TextEditingController();
  bool _isInitialized = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.file(widget.videoFile);
    _videoController
        .initialize()
        .then((_) {
          if (mounted) {
            setState(() {
              _isInitialized = true;
            });
            _videoController.setLooping(true);
            _videoController.play();
          }
        })
        .catchError((e) {
          debugPrint("Reel local video preview initialize error: $e");
        });
  }

  @override
  void dispose() {
    _videoController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.mode == 'story'
              ? 'New Story'
              : widget.mode == 'reel'
              ? 'New Reel'
              : 'New Video Post',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isUploading ? null : _shareReel,
            child: const Text(
              'Share',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Video Preview Box
                Container(
                  width: double.infinity,
                  height: widget.mode == 'story'
                      ? MediaQuery.of(context).size.height * 0.8
                      : MediaQuery.of(context).size.height * 0.5,
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[800]!, width: 0.5),
                    ),
                  ),
                  child: _isInitialized
                      ? Center(
                          child: AspectRatio(
                            aspectRatio: _videoController.value.aspectRatio,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(_videoController),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (_videoController.value.isPlaying) {
                                        _videoController.pause();
                                      } else {
                                        _videoController.play();
                                      }
                                    });
                                  },
                                  child: Container(
                                    color: Colors.transparent,
                                    child: Center(
                                      child: Icon(
                                        _videoController.value.isPlaying
                                            ? Icons.pause_circle_outline
                                            : Icons.play_circle_outline,
                                        size: 64,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                ),

                // Caption box
                if (widget.mode != 'story') ...[
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundImage: widget.currentUser.photoUrl != null
                              ? NetworkImage(widget.currentUser.photoUrl!)
                              : null,
                          child: widget.currentUser.photoUrl == null
                              ? Text(
                                  widget.currentUser.displayName.isNotEmpty
                                      ? widget.currentUser.displayName[0]
                                            .toUpperCase()
                                      : '?',
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _captionController,
                            maxLines: 4,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: widget.mode == 'reel'
                                  ? "Write a caption for your Reel..."
                                  : "Write a caption for your video...",
                              hintStyle: const TextStyle(
                                color: Colors.white30,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                ],

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    widget.mode == 'story'
                        ? 'Your video will be shared as a story for 24 hours.'
                        : widget.mode == 'reel'
                        ? 'Your Reel will be shared to the Reels tab and can be discovered by anyone.'
                        : 'Your video will be shared to the Home feed.',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // Loading spinner
          if (_isUploading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.75),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        widget.mode == 'story'
                            ? 'Sharing your story...'
                            : widget.mode == 'reel'
                            ? 'Sharing your Reel...'
                            : 'Sharing your video...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _isActionRunning = false;

  Future<void> _shareReel() async {
    if (_isActionRunning) return;

    final caption = _captionController.text.trim();

    setState(() {
      _isUploading = true;
      _isActionRunning = true;
    });

    try {
      // Compress video file client-side before uploading
      File finalVideoFile = widget.videoFile;
      if (mounted) {
        finalVideoFile = await VideoCompressionService.compressVideo(
          context,
          widget.videoFile,
        );
      }
      final String fileName =
          '${DateTime.now().millisecondsSinceEpoch}_video.mp4';
      final String folder = widget.mode == 'story'
          ? 'stories_video'
          : widget.mode == 'reel'
          ? 'reels_video'
          : 'posts_video';
      final refStorage = FirebaseStorage.instance.ref().child(
        '$folder/$fileName',
      );
      final uploadTask = await refStorage.putFile(finalVideoFile);
      final videoUrl = await uploadTask.ref.getDownloadURL();

      // Generate video thumbnail client-side
      final thumbnailFile = await VideoCompress.getFileThumbnail(
        finalVideoFile.path,
        quality: 50,
      );
      final String thumbFileName =
          '${DateTime.now().millisecondsSinceEpoch}_video_thumb.jpg';
      final String thumbFolder = widget.mode == 'story'
          ? 'stories_thumbnail'
          : widget.mode == 'reel'
          ? 'reels_thumbnail'
          : 'posts_thumbnail';
      final refThumb = FirebaseStorage.instance.ref().child(
        '$thumbFolder/$thumbFileName',
      );
      final uploadThumbTask = await refThumb.putFile(thumbnailFile);
      final thumbnailUrl = await uploadThumbTask.ref.getDownloadURL();

      // Add document to Firestore
      if (widget.mode == 'story') {
        await FirebaseFirestore.instance.collection('stories').add({
          'uid': widget.currentUser.uid,
          'displayName': widget.currentUser.displayName,
          'photoUrl': widget.currentUser.photoUrl,
          'type': 'video',
          'text': caption,
          'mediaUrl': videoUrl,
          'gradientIndex': 0,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else if (widget.mode == 'reel') {
        await FirebaseFirestore.instance.collection('reels').add({
          'videoUrl': videoUrl,
          'thumbnail': thumbnailUrl,
          'caption': caption,
          'uid': widget.currentUser.uid,
          'displayName': widget.currentUser.displayName,
          'photoUrl': widget.currentUser.photoUrl,
          'likes': <String>[],
          'commentsCount': 0,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseFirestore.instance.collection('posts').add({
          'uid': widget.currentUser.uid,
          'displayName': widget.currentUser.displayName,
          'photoUrl': widget.currentUser.photoUrl,
          'text': caption,
          'mediaUrl': videoUrl,
          'thumbnailUrl': thumbnailUrl,
          'type': 'video',
          'timestamp': FieldValue.serverTimestamp(),
          'likes': <String>[],
        });
      }

      if (mounted) {
        TopNotificationService.showSuccess(
          context,
          widget.mode == 'story'
              ? 'Story shared successfully!'
              : widget.mode == 'reel'
              ? 'Reel shared successfully!'
              : 'Video post shared successfully!',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Failed to share: $e");
      if (mounted) {
        TopNotificationService.showError(context, 'Failed to share: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _isActionRunning = false;
        });
      }
    }
  }
}
