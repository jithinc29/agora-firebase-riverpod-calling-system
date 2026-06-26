import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:video_compress/video_compress.dart';

import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/home/presentation/screens/home_screen.dart' show AppColors;
import 'package:photo_manager/photo_manager.dart';
import 'package:call_project/features/home/presentation/utils/video_compression_service.dart';
import 'package:call_project/features/home/presentation/screens/custom_gallery_picker.dart';
import 'package:call_project/features/home/presentation/screens/image_editor_screen.dart';
import 'package:call_project/features/home/presentation/screens/reel_upload_screen.dart';
import 'package:call_project/core/providers/refresh_provider.dart';
import 'package:call_project/core/services/notification_service.dart';

class PostCreatorCard extends ConsumerStatefulWidget {
  final UserModel currentUser;
  final VoidCallback onPostCreated;

  const PostCreatorCard({
    super.key,
    required this.currentUser,
    required this.onPostCreated,
  });

  @override
  ConsumerState<PostCreatorCard> createState() => _PostCreatorCardState();
}

class _PostCreatorCardState extends ConsumerState<PostCreatorCard> {
  final TextEditingController _postController = TextEditingController();
  File? _inlinePostMediaFile;
  String? _inlinePostMediaType;
  bool _isPosting = false;

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
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

  Future<void> _pickInlinePostMedia(ImageSource source, String type) async {
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
              currentUser: widget.currentUser,
              mode: 'post',
              initialCaption: _postController.text,
              onSuccess: () {
                _postController.clear();
                widget.onPostCreated();
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
              currentUser: widget.currentUser,
              mode: 'post', // Upload as video post
            ),
          ),
        );
        if (result == true && context.mounted) {
          _postController.clear();
          widget.onPostCreated();
        }
      }
    }
  }

  void _createPost() async {
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
        'uid': widget.currentUser.uid,
        'displayName': widget.currentUser.displayName,
        'photoUrl': widget.currentUser.photoUrl,
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
        widget.onPostCreated();
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

  @override
  Widget build(BuildContext context) {
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
                backgroundImage: widget.currentUser.photoUrl != null
                    ? CachedNetworkImageProvider(widget.currentUser.photoUrl!)
                    : null,
                child: widget.currentUser.photoUrl == null
                    ? Text(
                        widget.currentUser.displayName.isNotEmpty
                            ? widget.currentUser.displayName[0].toUpperCase()
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
                  decoration: InputDecoration(
                    hintText: "What's on your mind?",
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () =>
                    _pickInlinePostMedia(ImageSource.gallery, 'image'),
                icon: Icon(
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
                onPressed: () =>
                    _pickInlinePostMedia(ImageSource.gallery, 'video'),
                icon: Icon(
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
                      onPressed: _createPost,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
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
}
