import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_compress/video_compress.dart';

class VideoCompressionService {
  static Future<File> compressVideo(BuildContext context, File videoFile) async {
    // Get file size in MB
    final fileSizeInBytes = videoFile.lengthSync();
    final fileSizeInMb = fileSizeInBytes / (1024 * 1024);

    // If video is already small enough (< 15 MB), skip the slow native compression entirely!
    // A 3-5 MB video uploads in 1 second, but compressing it takes 30+ seconds.
    if (fileSizeInMb < 15.0) {
      debugPrint("🚀 Skipping compression: Video is already small (${fileSizeInMb.toStringAsFixed(2)} MB).");
      return videoFile;
    }

    // Show a progress dialog
    final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0.0);
    
    // Subscribe to progress streams from the native package
    final subscription = VideoCompress.compressProgress$.subscribe((progress) {
      progressNotifier.value = progress;
    });

    // Display progress dialog to keep the user informed during native compression
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                const CircularProgressIndicator(
                  color: Colors.deepPurple,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Optimizing video size...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This makes uploading faster and saves mobile data.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (context, val, child) {
                    return Text(
                      '${val.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                        fontSize: 14,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final mediaInfo = await VideoCompress.compressVideo(
        videoFile.path,
        quality: VideoQuality.DefaultQuality,
        deleteOrigin: false,
      );

      // Dismiss dialog
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      subscription.unsubscribe();

      if (mediaInfo != null && mediaInfo.file != null) {
        final compressedFile = mediaInfo.file!;
        debugPrint("Video compression success! Original: ${videoFile.lengthSync()} bytes -> Compressed: ${compressedFile.lengthSync()} bytes");
        return compressedFile;
      }
    } catch (e) {
      debugPrint("Video compression error: $e");
      // Dismiss dialog
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      subscription.unsubscribe();
    }

    // Fallback to original file to never block user flow in case of error
    return videoFile;
  }
}
