import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:call_project/core/theme/app_colors.dart';

class CustomAvatar extends StatelessWidget {
  final String? photoUrl;
  final double radius;

  const CustomAvatar({
    super.key,
    required this.photoUrl,
    this.radius = 25.0,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withOpacity(0.1),
      backgroundImage: photoUrl != null && photoUrl!.isNotEmpty
          ? CachedNetworkImageProvider(photoUrl!)
          : null,
      child: (photoUrl == null || photoUrl!.isEmpty)
          ? Icon(
              Icons.person,
              color: AppColors.primary,
              size: radius * 1.2,
            )
          : null,
    );
  }
}
