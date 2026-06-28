import 'package:cloud_firestore/cloud_firestore.dart';

int parseTimestamp(dynamic timestamp) {
  if (timestamp == null) return 0;
  if (timestamp is Timestamp) {
    return timestamp.millisecondsSinceEpoch;
  }
  if (timestamp is int) {
    return timestamp;
  }
  if (timestamp is double) {
    return timestamp.toInt();
  }
  if (timestamp is String) {
    return int.tryParse(timestamp) ?? 0;
  }
  return 0;
}

String formatLastSeen(DateTime? lastSeen, DateTime now) {
  if (lastSeen == null) return 'Never';
  final difference = now.difference(lastSeen);
  if (difference.inMinutes < 60) return 'Active ${difference.inMinutes}m ago';
  if (difference.inHours < 24) return 'Active ${difference.inHours}h ago';
  return 'Active ${difference.inDays}d ago';
}
