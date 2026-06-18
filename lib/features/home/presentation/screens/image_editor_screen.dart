import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/core/services/notification_service.dart';

class ImageEditorScreen extends StatefulWidget {
  final File imageFile;
  final UserModel currentUser;
  final String mode; // 'story' or 'post'
  final String? initialCaption;
  final VoidCallback? onSuccess;

  const ImageEditorScreen({
    super.key,
    required this.imageFile,
    required this.currentUser,
    required this.mode,
    this.initialCaption,
    this.onSuccess,
  });

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  bool _shouldPreventClose = false;

  @override
  Widget build(BuildContext context) {
    return ProImageEditor.file(
      widget.imageFile,
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (Uint8List bytes) async {
          _shouldPreventClose = true;
          LoadingDialog.instance.hide();
          if (widget.mode == 'post') {
            final bool? published = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (context) => PostPublishScreen(
                  bytes: bytes,
                  currentUser: widget.currentUser,
                  initialCaption: widget.initialCaption,
                ),
              ),
            );
            if (published == true && context.mounted) {
              _shouldPreventClose = false;
              widget.onSuccess?.call();
            }
          } else if (widget.mode == 'story') {
            await _publishStory(bytes);
          }
        },
        onCloseEditor: (dynamic mode) {
          if (_shouldPreventClose) {
            _shouldPreventClose = false;
            return;
          }
          Navigator.pop(context);
        },
      ),
      configs: ProImageEditorConfigs(
        designMode: Platform.isIOS ? ImageEditorDesignMode.cupertino : ImageEditorDesignMode.material,
        cropRotateEditor: const CropRotateEditorConfigs(),
        filterEditor: const FilterEditorConfigs(),
        blurEditor: const BlurEditorConfigs(),
        paintEditor: const PaintEditorConfigs(),
        mainEditor: const MainEditorConfigs(
          tools: [
            SubEditorMode.paint,
            SubEditorMode.text,
            SubEditorMode.cropRotate,
            SubEditorMode.tune,
            SubEditorMode.filter,
            SubEditorMode.blur,
            SubEditorMode.sticker,
          ],
        ),
        textEditor: const TextEditorConfigs(),
        emojiEditor: const EmojiEditorConfigs(),
        stickerEditor: StickerEditorConfigs(
          builder: (setLayer, scrollController) {
            final List<IconData> stickersList = [
              Icons.favorite,
              Icons.star,
              Icons.thumb_up,
              Icons.celebration,
              Icons.pets,
              Icons.wb_sunny,
              Icons.brightness_2,
              Icons.flash_on,
              Icons.music_note,
              Icons.local_fire_department,
            ];
            return Container(
              decoration: const BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                controller: scrollController,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: stickersList.length,
                itemBuilder: (context, index) {
                  final icon = stickersList[index];
                  return GestureDetector(
                    onTap: () {
                      setLayer(
                        WidgetLayer(
                          widget: Icon(
                            icon,
                            color: Colors.amber,
                            size: 64,
                          ),
                        ),
                      );
                    },
                    child: Icon(icon, color: Colors.white70, size: 36),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }


  void _showProgressDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const CircularProgressIndicator(color: Colors.deepPurple),
              const SizedBox(height: 24),
              Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _publishStory(Uint8List bytes) async {
    _showProgressDialog(context, 'Sharing your story...');
    try {
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/temp_story_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_story.png';
      final refStorage = FirebaseStorage.instance.ref().child('stories_image/$fileName');
      await refStorage.putFile(file);
      final mediaUrl = await refStorage.getDownloadURL();

      await FirebaseFirestore.instance.collection('stories').add({
        'uid': widget.currentUser.uid,
        'displayName': widget.currentUser.displayName,
        'photoUrl': widget.currentUser.photoUrl,
        'type': 'image',
        'text': '',
        'mediaUrl': mediaUrl,
        'gradientIndex': 0,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        // Pop loading progress dialog
        Navigator.of(context, rootNavigator: true).pop();
        _shouldPreventClose = false;
        TopNotificationService.showSuccess(context, 'Story shared successfully!');
        widget.onSuccess?.call();
      }
    } catch (e) {
      debugPrint("Failed to upload edited story: $e");
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        TopNotificationService.showError(context, 'Failed to share story: $e');
      }
    }
  }}

class PostPublishScreen extends StatefulWidget {
  final Uint8List bytes;
  final UserModel currentUser;
  final String? initialCaption;

  const PostPublishScreen({
    super.key,
    required this.bytes,
    required this.currentUser,
    this.initialCaption,
  });

  @override
  State<PostPublishScreen> createState() => _PostPublishScreenState();
}

class _PostPublishScreenState extends State<PostPublishScreen> {
  late final TextEditingController _captionController;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  void _showProgressDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const CircularProgressIndicator(color: Color(0xFF6366F1)),
              const SizedBox(height: 24),
              Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _publishPost() async {
    setState(() => _isPublishing = true);
    _showProgressDialog(context, 'Publishing your post...');
    try {
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/temp_post_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(widget.bytes);

      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_post.png';
      final refStorage = FirebaseStorage.instance.ref().child('posts_image/$fileName');
      await refStorage.putFile(file);
      final mediaUrl = await refStorage.getDownloadURL();

      await FirebaseFirestore.instance.collection('posts').add({
        'uid': widget.currentUser.uid,
        'displayName': widget.currentUser.displayName,
        'photoUrl': widget.currentUser.photoUrl,
        'text': _captionController.text.trim(),
        'mediaUrl': mediaUrl,
        'thumbnailUrl': null,
        'type': 'image',
        'timestamp': FieldValue.serverTimestamp(),
        'likes': <String>[],
      });

      if (mounted) {
        // Pop loading progress dialog
        Navigator.of(context, rootNavigator: true).pop();
        TopNotificationService.showSuccess(context, 'Post shared successfully!');
        Navigator.pop(context, true); // Return true to pop the editor
      }
    } catch (e) {
      debugPrint("Failed to upload edited post: $e");
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        TopNotificationService.showError(context, 'Failed to publish post: $e');
        setState(() => _isPublishing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Slate light background
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        title: const Text(
          'New Post',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User info and Caption input in a clean row
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: widget.currentUser.photoUrl != null &&
                                  widget.currentUser.photoUrl!.isNotEmpty
                              ? NetworkImage(widget.currentUser.photoUrl!)
                              : null,
                          child: widget.currentUser.photoUrl == null ||
                                  widget.currentUser.photoUrl!.isEmpty
                              ? const Icon(Icons.person, color: Colors.grey)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _captionController,
                            maxLines: 4,
                            maxLength: 2200,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF1E293B),
                              height: 1.4,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Write a caption...',
                              hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                              border: InputBorder.none,
                              counterText: '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24, thickness: 1),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Character Count',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                        AnimatedBuilder(
                          animation: _captionController,
                          builder: (context, _) {
                            return Text(
                              '${_captionController.text.length} / 2200',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Image Preview
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 1, // Keep it square
                    child: Image.memory(
                      widget.bytes,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // Publish Button
              ElevatedButton(
                onPressed: _isPublishing ? null : _publishPost,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF6366F1), // Indigo
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                child: const Text(
                  'Publish Post',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
