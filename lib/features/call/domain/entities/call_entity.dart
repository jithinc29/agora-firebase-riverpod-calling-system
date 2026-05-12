class CallEntity {
  final String callerId;
  final String callerName;
  final String receiverId;
  final String receiverName;
  final String channelId;
  final String status;
  final bool isAudioCall;

  CallEntity({
    required this.callerId,
    required this.callerName,
    required this.receiverId,
    required this.receiverName,
    required this.channelId,
    this.status = 'dialing',
    this.isAudioCall = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'callerId': callerId,
      'callerName': callerName,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'channelId': channelId,
      'status': status,
      'isAudioCall': isAudioCall,
    };
  }

  factory CallEntity.fromMap(Map<String, dynamic> map) {
    return CallEntity(
      callerId: map['callerId'] ?? '',
      callerName: map['callerName'] ?? '',
      receiverId: map['receiverId'] ?? '',
      receiverName: map['receiverName'] ?? '',
      channelId: map['channelId'] ?? '',
      status: map['status'] ?? 'dialing',
      isAudioCall: map['isAudioCall'] ?? false,
    );
  }
}
