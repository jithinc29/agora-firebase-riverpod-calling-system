import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/legacy.dart';

class UserPostsNotifier extends StateNotifier<List<DocumentSnapshot>> {
  UserPostsNotifier() : super([]);

  void init(List<DocumentSnapshot> initialPosts, int initialIndex) {
    if (initialIndex > 0 && initialIndex < initialPosts.length) {
      state = List.from(initialPosts.sublist(initialIndex));
    } else {
      state = List.from(initialPosts);
    }
  }

  void removePost(String id) {
    state = state.where((p) => p.id != id).toList();
  }
}

final userPostsProvider =
    StateNotifierProvider.autoDispose<
      UserPostsNotifier,
      List<DocumentSnapshot>
    >((ref) => UserPostsNotifier());
