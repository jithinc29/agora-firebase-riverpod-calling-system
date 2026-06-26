import 'package:call_project/core/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/core/utils/time_utils.dart';
import 'package:call_project/features/home/presentation/screens/home_screen.dart'
    show AppColors;
import 'package:cached_network_image/cached_network_image.dart';

class CommentsBottomSheetHelper {
  static void show(
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
                            buildCommentItem(
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
                              onLongPress: () => showCommentOptions(
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
                                child: buildCommentItem(
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
                                  onLongPress: () => showCommentOptions(
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

  static void showCommentOptions(
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

  static Widget buildCommentItem({
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
}
