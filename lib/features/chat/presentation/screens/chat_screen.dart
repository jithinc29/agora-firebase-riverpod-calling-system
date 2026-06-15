import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uuid/uuid.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/chat/models/message_model.dart';
import 'package:call_project/features/chat/data/repository/chat_repository.dart';
import 'package:call_project/core/providers/firebase_providers.dart';
import 'package:call_project/features/auth/repository/auth_repository.dart';
import 'package:intl/intl.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final UserModel receiver;
  const ChatScreen({super.key, required this.receiver});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  
  final Set<String> _selectedMessageIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _markAsRead();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _markAsRead() {
    final currentUser = ref.read(firebaseAuthProvider).currentUser;
    if (currentUser != null) {
      ref.read(chatRepositoryProvider).markMessagesAsRead(currentUser.uid, widget.receiver.uid);
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final currentUser = ref.read(firebaseAuthProvider).currentUser;
    if (currentUser == null) return;

    final message = MessageModel(
      id: const Uuid().v4(),
      senderId: currentUser.uid,
      receiverId: widget.receiver.uid,
      content: text,
      type: MessageType.text,
      timestamp: DateTime.now(),
    );

    ref.read(chatRepositoryProvider).sendMessage(message);
    _messageController.clear();
    setState(() {}); 
  }

  void _toggleSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        if (_selectedMessageIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedMessageIds.add(messageId);
        _isSelectionMode = true;
      }
    });
  }

  void _deleteSelectedMessages() {
    final currentUser = ref.read(firebaseAuthProvider).currentUser;
    if (currentUser == null) return;

    for (var id in _selectedMessageIds) {
      ref.read(chatRepositoryProvider).deleteMessage(currentUser.uid, widget.receiver.uid, id);
    }

    setState(() {
      _selectedMessageIds.clear();
      _isSelectionMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(firebaseAuthProvider).currentUser;
    final messagesAsync = currentUser != null
        ? ref.watch(chatMessagesProvider(currentUserId: currentUser.uid, receiverId: widget.receiver.uid))
        : const AsyncValue.loading();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE0F2FE), Color(0xFFFEF3C7), Color(0xFFFCE7F3)],
              ),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: messagesAsync.when(
                  data: (messages) {
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 100, 16, 16),
                      reverse: true,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final isMe = message.senderId == currentUser?.uid;
                        final isSelected = _selectedMessageIds.contains(message.id);
                        
                        return GestureDetector(
                          onLongPress: isMe ? () => _toggleSelection(message.id) : null,
                          onTap: _isSelectionMode ? () => _toggleSelection(message.id) : null,
                          child: Container(
                            color: isSelected ? Colors.purple.withValues(alpha: 0.1) : Colors.transparent,
                            child: _buildMessageBubble(message, isMe),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, st) => Center(child: Text('Error: $e')),
                ),
              ),
              _buildInputBar(),
            ],
          ),
        ],
      ),
    );
  }

  AppBar _buildNormalAppBar() {
    return AppBar(
      backgroundColor: Colors.white.withValues(alpha: 0.8),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.chevron_left, color: Color(0xFF1A1C1E), size: 30),
        onPressed: () => Navigator.pop(context),
      ),
      centerTitle: true,
      title: Column(
        children: [
          Text(widget.receiver.displayName, style: const TextStyle(color: Color(0xFF1A1C1E), fontWeight: FontWeight.bold, fontSize: 16)),
          Text(widget.receiver.isOnline ? 'Online' : 'Offline', style: TextStyle(color: widget.receiver.isOnline ? Colors.green : Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: Colors.purple,
      elevation: 4,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: () => setState(() {
          _selectedMessageIds.clear();
          _isSelectionMode = false;
        }),
      ),
      title: Text('${_selectedMessageIds.length} selected', style: const TextStyle(color: Colors.white)),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.white),
          onPressed: _deleteSelectedMessages,
        ),
      ],
    );
  }

  Widget _buildMessageBubble(MessageModel message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) _buildAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF6366F1) : Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isMe ? 20 : 5),
                  bottomRight: Radius.circular(isMe ? 5 : 20),
                ),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (message.type == MessageType.text)
                    Text(message.content, style: TextStyle(color: isMe ? Colors.white : const Color(0xFF1A1C1E), fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('HH:mm').format(message.timestamp),
                    style: TextStyle(color: (isMe ? Colors.white70 : Colors.grey.shade400), fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isMe) _buildAvatar(isMe: true),
        ],
      ),
    );
  }

  Widget _buildAvatar({bool isMe = false}) {
    final photoUrl = isMe ? ref.read(currentUserDataProvider).asData?.value?.photoUrl : widget.receiver.photoUrl;
    return CircleAvatar(
      radius: 18,
      backgroundImage: photoUrl != null ? CachedNetworkImageProvider(photoUrl) : null,
      child: photoUrl == null ? Text(isMe ? 'Me' : widget.receiver.displayName[0], style: const TextStyle(fontSize: 10)) : null,
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _messageController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Message...', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.purple),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}
