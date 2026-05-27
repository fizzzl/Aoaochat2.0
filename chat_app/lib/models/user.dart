// chat_app/lib/models/user.dart
class User {
  final int id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarThumbUrl;
  final String? phone;
  final bool isAdmin;
  final DateTime? lastSeenAt;
  final String? status; // online, offline, background

  User({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.avatarThumbUrl,
    this.phone,
    this.isAdmin = false,
    this.lastSeenAt,
    this.status,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] ?? json['userId'] ?? 0,
    username: json['username'] ?? '',
    displayName: json['display_name'] ?? json['displayName'] ?? '',
    avatarUrl: json['avatar_url'] ?? json['avatarUrl'],
    avatarThumbUrl: json['avatar_thumb_url'] ?? json['avatarThumbUrl'],
    phone: json['phone'],
    isAdmin: json['is_admin'] ?? json['isAdmin'] ?? false,
    lastSeenAt: json['last_seen_at'] != null
      ? DateTime.tryParse(json['last_seen_at']) : null,
    status: json['status'],
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'username': username, 'displayName': displayName,
    'avatarUrl': avatarUrl, 'avatarThumbUrl': avatarThumbUrl,
    'phone': phone, 'isAdmin': isAdmin,
  };
}
