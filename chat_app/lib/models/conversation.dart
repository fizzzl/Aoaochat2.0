// chat_app/lib/models/conversation.dart
class Conversation {
  final int id;
  final String type;
  final String? name;
  final String? displayName;
  final int? otherUserId;
  final String? avatarUrl;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  bool isPinned;

  Conversation({
    required this.id,
    this.type = 'private',
    this.name,
    this.displayName,
    this.otherUserId,
    this.avatarUrl,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isPinned = false,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] ?? 0,
    type: json['type'] ?? 'private',
    name: json['name'],
    displayName: json['display_name'] ?? json['displayName'],
    otherUserId: json['other_user_id'] ?? json['otherUserId'],
    avatarUrl: json['avatar_url'] ?? json['avatarUrl'],
    lastMessage: json['last_message'] ?? json['lastMessage'],
    lastMessageTime: json['last_message_time'] != null
      ? DateTime.tryParse(json['last_message_time']) : null,
    unreadCount: json['unread_count'] ?? json['unreadCount'] ?? 0,
  );
}
