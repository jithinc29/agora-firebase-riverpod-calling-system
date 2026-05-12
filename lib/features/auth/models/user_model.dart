class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final bool isOnline;
  final String? lastCallId;
  final String? fcmToken;
  final DateTime? lastSeen;
  final String? phoneNumber;
  final String? photoUrl;
  final List<String> followers;
  final List<String> following;
  final List<String> blockedUsers;
  final List<String> pendingFollowRequests; // UIDs of people requesting to follow ME

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.isOnline = false,
    this.lastCallId,
    this.fcmToken,
    this.lastSeen,
    this.phoneNumber,
    this.photoUrl,
    this.followers = const [],
    this.following = const [],
    this.blockedUsers = const [],
    this.pendingFollowRequests = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'isOnline': isOnline,
      'lastCallId': lastCallId,
      'fcmToken': fcmToken,
      'lastSeen': lastSeen?.millisecondsSinceEpoch,
      'phoneNumber': phoneNumber,
      'photoUrl': photoUrl,
      'followers': followers,
      'following': following,
      'blockedUsers': blockedUsers,
      'pendingFollowRequests': pendingFollowRequests,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      displayName: map['displayName'] ?? '',
      isOnline: map['isOnline'] ?? false,
      lastCallId: map['lastCallId'],
      fcmToken: map['fcmToken'],
      lastSeen: map['lastSeen'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['lastSeen']) 
          : null,
      phoneNumber: map['phoneNumber'],
      photoUrl: map['photoUrl'],
      followers: List<String>.from(map['followers'] ?? []),
      following: List<String>.from(map['following'] ?? []),
      blockedUsers: List<String>.from(map['blockedUsers'] ?? []),
      pendingFollowRequests: List<String>.from(map['pendingFollowRequests'] ?? []),
    );
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    bool? isOnline,
    String? lastCallId,
    String? fcmToken,
    DateTime? lastSeen,
    String? phoneNumber,
    String? photoUrl,
    List<String>? followers,
    List<String>? following,
    List<String>? blockedUsers,
    List<String>? pendingFollowRequests,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      isOnline: isOnline ?? this.isOnline,
      lastCallId: lastCallId ?? this.lastCallId,
      fcmToken: fcmToken ?? this.fcmToken,
      lastSeen: lastSeen ?? this.lastSeen,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      blockedUsers: blockedUsers ?? this.blockedUsers,
      pendingFollowRequests: pendingFollowRequests ?? this.pendingFollowRequests,
    );
  }
}
