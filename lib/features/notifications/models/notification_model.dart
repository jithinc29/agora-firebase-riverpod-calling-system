
enum NotificationType { followRequest, missedCall, message }

class NotificationModel {
  final String id;
  final String receiverId;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? extraData;

  NotificationModel({
    required this.id,
    required this.receiverId,
    required this.senderId,
    required this.senderName,
    this.senderPhotoUrl,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.extraData,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receiverId': receiverId,
      'senderId': senderId,
      'senderName': senderName,
      'senderPhotoUrl': senderPhotoUrl,
      'title': title,
      'body': body,
      'type': type.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isRead': isRead,
      'extraData': extraData,
    };
  }

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'] ?? '',
      receiverId: map['receiverId'] ?? '',
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? '',
      senderPhotoUrl: map['senderPhotoUrl'],
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      type: NotificationType.values.firstWhere(
        (e) => e.name == (map['type'] ?? 'message'),
        orElse: () => NotificationType.message,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
      isRead: map['isRead'] ?? false,
      extraData: map['extraData'],
    );
  }
}
