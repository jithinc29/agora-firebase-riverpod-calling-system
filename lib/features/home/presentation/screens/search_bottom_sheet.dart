import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:call_project/features/auth/models/user_model.dart';
import 'package:call_project/features/users/presentation/screens/user_profile_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AppColors {
  static const primary = Color(0xFF6366F1);
  static const secondary = Color(0xFFA855F7);
  static const background = Color(0xFFF8FAFC);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
}

class SearchBottomSheet extends StatefulWidget {
  final AsyncValue<List<UserModel>> usersAsync;
  final User? currentUser;

  const SearchBottomSheet({
    super.key,
    required this.usersAsync,
    required this.currentUser,
  });

  @override
  State<SearchBottomSheet> createState() => _SearchBottomSheetState();
}

class _SearchBottomSheetState extends State<SearchBottomSheet> {
  String _searchQuery = '';
  final Set<String> _removedUserIds = {};
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus the search field when the sheet opens
    Future.delayed(const Duration(milliseconds: 100), () {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine if app is in dark mode
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode ? Colors.black : Colors.white;
    final textColor = isDarkMode ? Colors.white : AppColors.textPrimary;
    final subTextColor = isDarkMode ? Colors.white54 : AppColors.textSecondary;
    final searchBgColor = isDarkMode
        ? const Color(0xFF262626)
        : Colors.grey.shade100;

    return Container(
      color: bgColor,
      child: Column(
        children: [
          // Custom Header matching the screenshot
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: textColor),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: TextStyle(color: subTextColor),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: subTextColor,
                      ),
                      filled: true,
                      fillColor: searchBgColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 16,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Divider(
            height: 1,
            color: isDarkMode ? Colors.white12 : Colors.grey.shade200,
          ),

          // Search Results
          Expanded(
            child: widget.usersAsync.when(
              data: (users) {
                final filteredUsers = users.where((u) {
                  if (u.uid == widget.currentUser?.uid) return false;
                  if (u.displayName.trim().isEmpty) return false;

                  final query = _searchQuery.trim().toLowerCase();

                  if (query.isEmpty) {
                    if (_removedUserIds.contains(u.uid)) return false;
                    return true;
                  }

                  return u.displayName.toLowerCase().contains(query);
                }).toList();

                if (filteredUsers.isEmpty) {
                  return Center(
                    child: Text(
                      'No results found',
                      style: TextStyle(color: subTextColor),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filteredUsers.length,
                  itemBuilder: (context, index) {
                    final user = filteredUsers[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundImage:
                            user.photoUrl != null && user.photoUrl!.isNotEmpty
                            ? CachedNetworkImageProvider(user.photoUrl!)
                            : null,
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        child: (user.photoUrl == null || user.photoUrl!.isEmpty)
                            ? Text(
                                user.displayName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        user.displayName,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        'User • ${user.isOnline ? 'Online' : 'Offline'}',
                        style: TextStyle(color: subTextColor, fontSize: 11),
                      ),
                      trailing: _searchQuery.trim().isEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: subTextColor,
                                size: 18,
                              ),
                              onPressed: () {
                                setState(() {
                                  _removedUserIds.add(user.uid);
                                });
                              },
                            )
                          : null,
                      onTap: () {
                        // Navigate to profile
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserProfileScreen(user: user),
                          ),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Error: $e', style: TextStyle(color: textColor)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
