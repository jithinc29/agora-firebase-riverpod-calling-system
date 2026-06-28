import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

class CustomGalleryPickerScreen extends StatefulWidget {
  final RequestType requestType;

  const CustomGalleryPickerScreen({super.key, required this.requestType});

  @override
  State<CustomGalleryPickerScreen> createState() =>
      _CustomGalleryPickerScreenState();
}

class _CustomGalleryPickerScreenState extends State<CustomGalleryPickerScreen> {
  final List<AssetEntity> _mediaList = [];
  AssetEntity? _selectedEntity;
  int _currentPage = 0;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isLimitedPermission = false;

  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _fetchMedia();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _fetchMedia() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      debugPrint('[CustomGallery] Permission State: $ps');

      if (mounted) {
        setState(() {
          _isLimitedPermission = ps == PermissionState.limited;
        });
      }

      if (ps.isAuth || ps == PermissionState.limited) {
        debugPrint(
          '[CustomGallery] Requesting albums for type: ${widget.requestType}',
        );
        final FilterOptionGroup filterOptionGroup = FilterOptionGroup(
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        );

        List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
          type: widget.requestType,
          hasAll: true,
          onlyAll: true,
          filterOption: filterOptionGroup,
        );

        debugPrint('[CustomGallery] Found ${albums.length} albums.');
        for (var album in albums) {
          debugPrint(
            '[CustomGallery] Album: ${album.name}, count: ${await album.assetCountAsync}',
          );
        }

        if (albums.isNotEmpty) {
          List<AssetEntity> media = [];

          // First try to get media from the 'Recent' (first) album
          media = await albums[0].getAssetListPaged(
            page: _currentPage,
            size: 30,
          );

          debugPrint(
            '[CustomGallery] Recent album returned ${media.length} items.',
          );

          // Fallback: If 'Recent' is empty, loop through other albums to find videos
          if (media.isEmpty && _currentPage == 0 && albums.length > 1) {
            for (int i = 1; i < albums.length; i++) {
              final albumMedia = await albums[i].getAssetListPaged(
                page: 0,
                size: 30,
              );
              debugPrint(
                '[CustomGallery] Fallback Album ${albums[i].name} returned ${albumMedia.length} items.',
              );
              if (albumMedia.isNotEmpty) {
                media = albumMedia;
                break;
              }
            }
          }

          if (mounted) {
            setState(() {
              _mediaList.addAll(media);
              if (media.isNotEmpty && _selectedEntity == null) {
                _selectEntity(media.first);
              }
              if (media.length < 30) {
                _hasMore = false;
              }
              _currentPage++;
            });
          }
        } else {
          if (mounted) setState(() => _hasMore = false);
        }
      } else {
        PhotoManager.openSetting();
      }
    } catch (e) {
      debugPrint("Error fetching media: $e");
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _selectEntity(AssetEntity entity) async {
    if (_selectedEntity == entity) return;

    setState(() {
      _selectedEntity = entity;
    });

    if (entity.type == AssetType.video) {
      final file = await entity.file;
      if (file != null) {
        _videoController?.dispose();
        _videoController = VideoPlayerController.file(file)
          ..initialize().then((_) {
            setState(() {});
            _videoController?.play();
            _videoController?.setLooping(true);
            _videoController?.setVolume(0);
          });
      }
    } else {
      _videoController?.pause();
      _videoController?.dispose();
      _videoController = null;
    }
  }

  Future<void> _takeCameraMedia() async {
    final picker = ImagePicker();
    XFile? file;
    if (widget.requestType == RequestType.video) {
      file = await picker.pickVideo(source: ImageSource.camera);
    } else {
      file = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
    }

    if (file != null && mounted) {
      final type = widget.requestType == RequestType.video ? 'video' : 'image';
      Navigator.pop(context, {'file': File(file.path), 'type': type});
    }
  }

  void _onNextTap() async {
    if (_selectedEntity != null) {
      final file = await _selectedEntity!.file;
      if (file != null && mounted) {
        final type = _selectedEntity!.type == AssetType.video
            ? 'video'
            : 'image';
        Navigator.pop(context, {'file': file, 'type': type});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.requestType == RequestType.video ? 'New reel' : 'New post',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: _selectedEntity != null ? _onNextTap : null,
            child: const Text(
              'Next',
              style: TextStyle(
                color: Colors.blue,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Preview Area
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.black,
              width: double.infinity,
              child: _selectedEntity == null
                  ? (_isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          )
                        : const Center(
                            child: Text(
                              'No media found',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ))
                  : _selectedEntity!.type == AssetType.video &&
                        _videoController != null &&
                        _videoController!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    )
                  : Image(
                      image: AssetEntityImageProvider(
                        _selectedEntity!,
                        isOriginal: true,
                        thumbnailSize: const ThumbnailSize.square(800),
                      ),
                      fit: BoxFit.contain,
                    ),
            ),
          ),

          // Recents Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.black,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox.shrink(),
                if (_isLimitedPermission)
                  GestureDetector(
                    onTap: () async {
                      await PhotoManager.presentLimited();
                      setState(() {
                        _mediaList.clear();
                        _currentPage = 0;
                        _hasMore = true;
                      });
                      _fetchMedia();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Manage Access',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.filter_none, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Select',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Bottom Grid Area
          Expanded(
            flex: 5,
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification scrollInfo) {
                if (!_isLoading &&
                    scrollInfo.metrics.pixels ==
                        scrollInfo.metrics.maxScrollExtent) {
                  _fetchMedia();
                }
                return false;
              },
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: _mediaList.length + 1, // +1 for camera
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return GestureDetector(
                      onTap: _takeCameraMedia,
                      child: Container(
                        color: Colors.grey[850],
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    );
                  }

                  final entity = _mediaList[index - 1];
                  final isSelected = entity == _selectedEntity;

                  return GestureDetector(
                    onTap: () => _selectEntity(entity),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image(
                          image: AssetEntityImageProvider(
                            entity,
                            isOriginal: false,
                            thumbnailSize: const ThumbnailSize.square(200),
                          ),
                          fit: BoxFit.cover,
                        ),
                        if (entity.type == AssetType.video)
                          const Positioned(
                            bottom: 4,
                            right: 4,
                            child: Icon(
                              Icons.play_circle_outline,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        if (isSelected)
                          Container(color: Colors.white.withOpacity(0.4)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
