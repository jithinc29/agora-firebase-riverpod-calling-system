import 'package:flutter/material.dart';
import 'package:call_project/core/theme/app_colors.dart';
import 'package:call_project/features/home/presentation/screens/home_screen.dart';

class FeedTab extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget postCreatorCard;
  final bool isLoading;
  final bool hasMore;
  final bool isEmpty;
  final ScrollController scrollController;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const FeedTab({
    super.key,
    required this.onRefresh,
    required this.postCreatorCard,
    required this.isLoading,
    required this.hasMore,
    required this.isEmpty,
    required this.scrollController,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.background),
      child: RefreshIndicator(
        onRefresh: onRefresh,
        color: AppColors.primary,
        child: Column(
          children: [
            postCreatorCard,
            Expanded(
              child: isEmpty && (isLoading || hasMore)
                  ? const Center(child: CircularProgressIndicator())
                  : isEmpty
                  ? const Center(
                      child: Text(
                        'No posts yet. Be the first to share!',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.only(top: 4, bottom: 78),
                      itemCount: itemCount,
                      itemBuilder: itemBuilder,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
