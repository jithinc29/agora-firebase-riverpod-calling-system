import re

with open(r'c:\flutter projects\call_project\lib\features\profile\presentation\screens\profile_screen.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# Replace build content
old_build_content = '''            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 10,
              ),
              child: Column(
                children: [
                  // Compact Profile Header Card
                  _buildProfileHeaderCard(user, activeFollowers, activeFollowing),
                  const SizedBox(height: 16),

                  // Bento 3: Follow Requests
                  _buildFollowRequests(user, activePendingRequests),

                  // Bento 4: Profile Details Fields
                  _buildProfileSection(user),
                  const SizedBox(height: 16),

                  // Bento 5: Preferences/Settings Card
                  _buildSettingsSection(),
                  const SizedBox(height: 24),

                  // Bento 6: Actions (Save & Logout)
                  _buildSaveButton(),
                  const SizedBox(height: 12),
                  _buildLogoutButton(),
                  SizedBox(height: widget.isEmbedded ? 120 : 40),
                ],
              ),
            );'''

new_build_content = '''            return DefaultTabController(
              length: 2,
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Column(
                          children: [
                            _buildProfileHeaderCard(user, activeFollowers, activeFollowing),
                            const SizedBox(height: 16),
                            _buildFollowRequests(user, activePendingRequests),
                          ],
                        ),
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SliverAppBarDelegate(
                        const TabBar(
                          indicatorColor: AppColors.primary,
                          labelColor: AppColors.primary,
                          unselectedLabelColor: AppColors.textSecondary,
                          tabs: [
                            Tab(icon: Icon(Icons.grid_on_rounded)),
                            Tab(icon: Icon(Icons.ondemand_video_rounded)),
                          ],
                        ),
                      ),
                    ),
                  ];
                },
                body: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchUserMedia(user.uid),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: \', style: TextStyle(color: Colors.red)));
                    }
                    final allMedia = snapshot.data ?? [];
                    final videosOnly = allMedia.where((m) => m['type'] == 'video').toList();

                    return TabBarView(
                      children: [
                        _buildMediaGrid(allMedia),
                        _buildMediaGrid(videosOnly),
                      ],
                    );
                  },
                ),
              ),
            );'''

code = code.replace(old_build_content, new_build_content)

# Add Edit Profile Button to Header
old_header_end = '''                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }'''

new_header_end = '''                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: OutlinedButton(
                    onPressed: () => _showEditProfileSheet(context, user),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(color: Colors.black.withOpacity(0.1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }'''

code = code.replace(old_header_end, new_header_end)

# Replace the remaining code block
parts = code.split('  Widget _buildProfileSection(UserModel user) {')
if len(parts) == 2:
    new_tail = '''
  void _showEditProfileSheet(BuildContext context, UserModel user) {
    _nameController.text = user.displayName;
    _phoneController.text = user.phoneNumber ?? '';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final viewInsets = MediaQuery.of(context).viewInsets;
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Edit Profile',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 24),
                    
                    _buildField('Display Name', _nameController, Icons.person_outline_rounded),
                    const SizedBox(height: 16),
                    _buildField('Phone Number', _phoneController, Icons.phone_outlined, keyboardType: TextInputType.phone),
                    const SizedBox(height: 32),
                    
                    const Text(
                      'Account Settings',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 16),
                    
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.block_rounded, color: AppColors.primary),
                      title: const Text('Blocked Users', style: TextStyle(fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockListScreen()));
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.logout_rounded, color: AppColors.primary),
                      title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w600)),
                      onTap: () {
                        Navigator.pop(context);
                        _signOut();
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.delete_forever_rounded, color: AppColors.error),
                      title: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.error)),
                      onTap: () {
                        Navigator.pop(context);
                        _showDeleteConfirmation();
                      },
                    ),
                    
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : () async {
                          setSheetState(() => _isSaving = true);
                          await _saveProfile();
                          setSheetState(() => _isSaving = false);
                          if (context.mounted) Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSaving 
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon, {
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          decoration: InputDecoration(
            icon: Icon(icon, color: AppColors.primary, size: 16),
            border: InputBorder.none,
            hintText: 'Enter \',
            hintStyle: TextStyle(
              color: AppColors.textSecondary.withOpacity(0.4),
              fontSize: 12,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _fetchUserMedia(String uid) async {
    final postsFuture = FirebaseFirestore.instance
        .collection('posts')
        .where('uid', isEqualTo: uid)
        .get();
    
    final reelsFuture = FirebaseFirestore.instance
        .collection('reels')
        .where('uid', isEqualTo: uid)
        .get();

    final results = await Future.wait([postsFuture, reelsFuture]);
    
    final postsDocs = results[0].docs;
    final reelsDocs = results[1].docs;

    final List<Map<String, dynamic>> allMedia = [];

    for (var doc in postsDocs) {
      final data = doc.data();
      if (data['type'] == 'image' || data['type'] == 'video') {
        data['id'] = doc.id;
        data['source'] = 'post';
        allMedia.add(data);
      }
    }

    for (var doc in reelsDocs) {
      final data = doc.data();
      data['id'] = doc.id;
      data['source'] = 'reel';
      data['type'] = 'video'; 
      allMedia.add(data);
    }

    allMedia.sort((a, b) {
      final aTime = (a['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final bTime = (b['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });

    return allMedia;
  }

  Widget _buildMediaGrid(List<Map<String, dynamic>> mediaList) {
    if (mediaList.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined, size: 48, color: Colors.black26),
            SizedBox(height: 16),
            Text('No Posts Yet', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 1,
      ),
      itemCount: mediaList.length,
      itemBuilder: (context, index) {
        final media = mediaList[index];
        final isVideo = media['type'] == 'video';
        final thumbnailUrl = isVideo ? media['thumbnailUrl'] : media['mediaUrl'];
        
        return GestureDetector(
          onTap: () {
            // Can open viewer later
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.grey.shade200),
              if (thumbnailUrl != null && thumbnailUrl.toString().isNotEmpty)
                CachedNetworkImage(
                  imageUrl: thumbnailUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              if (isVideo)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.play_circle_outline_rounded, color: Colors.white, size: 20, shadows: [Shadow(color: Colors.black45, blurRadius: 4)]),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
'''
    code = parts[0] + new_tail

with open(r'c:\flutter projects\call_project\lib\features\profile\presentation\screens\profile_screen.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("Refactor complete")
