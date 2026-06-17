import 'package:call_project/core/utils/time_utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/core/services/notification_service.dart';
import 'package:call_project/features/home/presentation/screens/home_screen.dart' show AppColors, feedMuteProvider, PostVideoPlayer;
import 'package:flutter/services.dart';
import 'package:call_project/core/providers/refresh_provider.dart';

  class FeedPostCard extends ConsumerStatefulWidget {
  final VoidCallback? onPostDeleted;
  final VoidCallback? onPostHidden;
  final DocumentSnapshot postDoc;
  final UserModel currentUser;
  const FeedPostCard({Key? key, required this.postDoc, required this.currentUser, this.onPostDeleted, this.onPostHidden}) : super(key: key);
  @override
  ConsumerState<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends ConsumerState<FeedPostCard> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    final data = widget.postDoc.data() as Map<String, dynamic>? ?? {};
    final isVideo = data['type'] == 'video' || data.containsKey('videoUrl');
    if (isVideo) {
      final url = data['mediaUrl'] ?? data['videoUrl'];
      if (url != null) {
        _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
        _videoController!.initialize().then((_) {
          if (mounted) setState(() { _isVideoInitialized = true; });
          _videoController!.setLooping(true);
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialPostDoc = widget.postDoc;
    final currentUser = widget.currentUser;

    return StreamBuilder<DocumentSnapshot>(
      stream: initialPostDoc.reference.snapshots(),
      builder: (context, snapshot) {
        final postDoc = snapshot.data ?? initialPostDoc;
        final data = postDoc.data() as Map<String, dynamic>? ?? {};
        final String displayName = data['displayName'] ?? 'Anonymous';
        final String? photoUrl = data['photoUrl'];
        final String text = data['text'] ?? data['caption'] ?? '';
        final List<dynamic> likes = data['likes'] ?? [];
        final int timestampMillis = parseTimestamp(data['timestamp']);
        final DateTime? timestampDate = timestampMillis > 0 ? DateTime.fromMillisecondsSinceEpoch(timestampMillis) : null;
        final String? type = data['type'] ?? (data.containsKey('videoUrl') ? 'video' : null);
        final String? mediaUrl = data['mediaUrl'] ?? data['videoUrl'];
        final String? thumbnailUrl = data['thumbnailUrl'] ?? data['thumbnail'];
    
    final isLiked = likes.contains(currentUser.uid);
    final likeCount = likes.length;

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
                backgroundImage: photoUrl != null ? CachedNetworkImageProvider(photoUrl) : null,
                child: photoUrl == null ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?') : null,
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
                onPressed: () => _showPostOptionsMenu(context, postDoc, currentUser.uid),
                icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textSecondary),
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
              GestureDetector(
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
                      isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isLiked ? Colors.red : AppColors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$likeCount',
                      style: TextStyle(
                        color: isLiked ? Colors.red : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: () => _showCommentsBottomSheet(context, postDoc, currentUser),
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
                      stream: postDoc.reference.collection('comments').snapshots(),
                      builder: (context, snapshot) {
                        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
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
                  final link = 'https://callingapp.page.link/post/${postDoc.id}';
                  Clipboard.setData(ClipboardData(text: link));
                  TopNotificationService.showSuccess(context, 'Post link copied to clipboard!');
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
      },
    );
  }

  Widget _buildPostCardMedia(String? type, String mediaUrl, String? thumbnailUrl) {
    if (type == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
          imageUrl: mediaUrl,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            height: 200,
            color: Colors.black12,
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
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
          child: PostVideoPlayer(videoUrl: mediaUrl, thumbnailUrl: thumbnailUrl),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _showPostOptionsMenu(BuildContext context, DocumentSnapshot postDoc, String currentUserId) {
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
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  title: const Text('Delete Post', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(sheetContext); // close bottom sheet
                    _confirmDeletePost(outerContext, postDoc); // use outer context for dialog
                  },
                ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined, color: AppColors.textPrimary),
                title: const Text('Hide Post', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (widget.onPostHidden != null) widget.onPostHidden!();
                  if (outerContext.mounted) {
                    TopNotificationService.showSuccess(outerContext, 'Post hidden');
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
        title: const Text('Delete Post', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to delete this post permanently? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final data = postDoc.data() as Map<String, dynamic>? ?? {};
                final mediaUrl = data['mediaUrl'] as String?;
                final videoUrl = data['videoUrl'] as String?;
                final thumbnail = data['thumbnail'] as String?;
                final thumbnailUrl = data['thumbnailUrl'] as String?;
                
                final urlsToDelete = [mediaUrl, videoUrl, thumbnail, thumbnailUrl].where((url) => url != null && url.isNotEmpty).toList();
                
                for (final url in urlsToDelete) {
                  try {
                    final storageRef = FirebaseStorage.instance.refFromURL(url!);
                    await storageRef.delete();
                  } catch (e) {
                    debugPrint('Failed to delete media from storage: $e');
                  }
                }
                await postDoc.reference.delete();
                if (widget.onPostDeleted != null) {
                  widget.onPostDeleted!();
                }
                ref.read(mediaRefreshProvider.notifier).state++;
                if (context.mounted) {
                  TopNotificationService.showSuccess(context, 'Post deleted successfully');
                }
              } catch (e) {
                if (context.mounted) {
                  TopNotificationService.showError(context, 'Failed to delete post: $e');
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCommentsBottomSheet(BuildContext context, DocumentSnapshot postDoc, UserModel currentUser) {
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
                          return Center(child: Text('Error: ${snapshot.error}'));
                        }
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final commentDocs = snapshot.data?.docs ?? [];
                        if (commentDocs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No comments yet. Start the conversation!',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
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

                        final Map<String, List<DocumentSnapshot>> repliesByParent = {};
                        for (var reply in replies) {
                          final data = reply.data() as Map<String, dynamic>;
                          final parentId = data['parentId'] as String;
                          repliesByParent.putIfAbsent(parentId, () => []).add(reply);
                        }

                        final currentUserUid = currentUser.uid;
                        final postAuthorUid = (postDoc.data() as Map<String, dynamic>?)?['uid'] as String?;

                        final List<Widget> listItems = [];
                        for (var parent in parentComments) {
                          final parentData = parent.data() as Map<String, dynamic>? ?? {};
                          final parentLikes = parentData['likes'] as List<dynamic>? ?? [];
                          listItems.add(
                            _buildCommentItem(
                              commentDoc: parent,
                              isReply: false,
                              isLiked: parentLikes.contains(currentUserUid),
                              likeCount: parentLikes.length,
                              onLikeTap: () {
                                final updatedLikes = List<String>.from(parentLikes.map((e) => e.toString()));
                                if (updatedLikes.contains(currentUserUid)) {
                                  updatedLikes.remove(currentUserUid);
                                } else {
                                  updatedLikes.add(currentUserUid);
                                }
                                parent.reference.update({'likes': updatedLikes});
                              },
                              onLongPress: () => _showCommentOptions(context, parent, currentUserUid, postAuthorUid),
                              onReplyTap: () {
                                final name = parentData['displayName'] ?? 'Anonymous';
                                setState(() {
                                  replyToCommentId = parent.id;
                                  replyToUsername = name;
                                  textController.text = '@$name ';
                                  textController.selection = TextSelection.fromPosition(
                                    TextPosition(offset: textController.text.length),
                                  );
                                });
                                focusNode.requestFocus();
                              },
                            ),
                          );

                          final parentReplies = repliesByParent[parent.id] ?? [];
                          for (var reply in parentReplies) {
                            final replyData = reply.data() as Map<String, dynamic>? ?? {};
                            final replyLikes = replyData['likes'] as List<dynamic>? ?? [];
                            listItems.add(
                              Padding(
                                padding: const EdgeInsets.only(left: 36.0),
                                child: _buildCommentItem(
                                  commentDoc: reply,
                                  isReply: true,
                                  isLiked: replyLikes.contains(currentUserUid),
                                  likeCount: replyLikes.length,
                                  onLikeTap: () {
                                    final updatedLikes = List<String>.from(replyLikes.map((e) => e.toString()));
                                    if (updatedLikes.contains(currentUserUid)) {
                                      updatedLikes.remove(currentUserUid);
                                    } else {
                                      updatedLikes.add(currentUserUid);
                                    }
                                    reply.reference.update({'likes': updatedLikes});
                                  },
                                  onLongPress: () => _showCommentOptions(context, reply, currentUserUid, postAuthorUid),
                                  onReplyTap: () {
                                    final name = replyData['displayName'] ?? 'Anonymous';
                                    setState(() {
                                      replyToCommentId = parent.id;
                                      replyToUsername = name;
                                      textController.text = '@$name ';
                                      textController.selection = TextSelection.fromPosition(
                                        TextPosition(offset: textController.text.length),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                                if (textController.text.trim().startsWith('@')) {
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
                      border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                    ),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: ['❤️', '🔥', '😂', '👏', '😍', '😢', '🙌', '😮'].map((emoji) {
                        return InkWell(
                          onTap: () {
                            final text = textController.text;
                            final selection = textController.selection;
                            String newText;
                            if (selection.isValid) {
                              newText = text.replaceRange(selection.start, selection.end, emoji);
                            } else {
                              newText = text + emoji;
                            }
                            textController.text = newText;
                            textController.selection = TextSelection.fromPosition(
                              TextPosition(offset: newText.length),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundImage: currentUser.photoUrl != null
                                ? CachedNetworkImageProvider(currentUser.photoUrl!)
                                : null,
                            child: currentUser.photoUrl == null
                                ? Text(
                                    currentUser.displayName.isNotEmpty
                                        ? currentUser.displayName[0].toUpperCase()
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
                                hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 8),
                              ),
                              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
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
                                await postDoc.reference.collection('comments').add(commentData);
                              } catch (e) {
                                if (context.mounted) {
                                  TopNotificationService.showError(
                                      context, 'Failed to add comment: $e');
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

    final canDelete = (currentUserUid == commentAuthorUid) || (currentUserUid == postAuthorUid);

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
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  title: const Text('Delete Comment', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    commentDoc.reference.delete();
                    Navigator.pop(context);
                  },
                ),
              if (!canDelete) ...[
                ListTile(
                  leading: const Icon(Icons.report_gmailerrorred_rounded, color: Colors.red),
                  title: const Text('Report', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    TopNotificationService.showSuccess(context, 'Comment reported');
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
    final DateTime? timestampDate = timestampMillis > 0 ? DateTime.fromMillisecondsSinceEpoch(timestampMillis) : null;

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
              backgroundImage: photoUrl != null ? CachedNetworkImageProvider(photoUrl) : null,
              child: photoUrl == null
                  ? Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
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
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
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
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
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
                    isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 14,
                    color: isLiked ? Colors.red : AppColors.textSecondary,
                  ),
                ),
                if (likeCount > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$likeCount',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }

}
