import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

final isStoryDialogOpenProvider = StateProvider<bool>((ref) => false);
final currentTabIndexProvider = StateProvider<int>((ref) => 0);
final feedVideoVisibilityProvider = StateProvider<Map<String, double>>(
  (ref) => {},
);

final activeFeedVideoProvider = Provider<String?>((ref) {
  final visibilities = ref.watch(feedVideoVisibilityProvider);
  if (visibilities.isEmpty) {
    return null;
  }

  String? mostVisible;
  double maxVis = 0.0;

  for (var entry in visibilities.entries) {
    if (entry.value > maxVis) {
      maxVis = entry.value;
      mostVisible = entry.key;
    }
  }

  if (maxVis >= 0.15) {
    return mostVisible;
  }
  return null;
});

class FeedMuteNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() {
    state = !state;
  }
}

final feedMuteProvider = NotifierProvider<FeedMuteNotifier, bool>(() {
  return FeedMuteNotifier();
});
