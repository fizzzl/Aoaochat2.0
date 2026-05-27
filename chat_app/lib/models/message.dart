// chat_app/lib/models/message.dart
enum MessageStatus { sending, sent, delivered, failed }

class Message {
  final int id;
  final int conversationId;
  final int senderId;
  final String senderUsername;
  final String senderDisplayName;
  final String type;
  final String content;
  final DateTime? readAt;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final String? tempId;
  MessageStatus status;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.senderUsername = '',
    this.senderDisplayName = '',
    this.type = 'text',
    required this.content,
    this.readAt,
    this.deletedAt,
    required this.createdAt,
    this.tempId,
    this.status = MessageStatus.sent,
  });

  bool get isRecalled => deletedAt != null;
  bool get isRead => readAt != null;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] ?? 0,
    conversationId: json['conversation_id'] ?? json['conversationId'] ?? 0,
    senderId: json['sender_id'] ?? json['senderId'] ?? 0,
    senderUsername: json['sender_username'] ?? json['senderUsername'] ?? '',
    senderDisplayName: json['sender_display_name'] ?? json['senderDisplayName'] ?? '',
    type: json['type'] ?? 'text',
    content: json['content'] ?? '',
    readAt: json['read_at'] != null ? DateTime.tryParse(json['read_at'] ?? json['readAt']) : null,
    deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'] ?? json['deletedAt']) : null,
    createdAt: DateTime.tryParse(json['created_at'] ?? json['createdAt'] ?? '') ?? DateTime.now(),
    tempId: json['tempId'],
    status: MessageStatus.sent,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'conversationId': conversationId, 'senderId': senderId,
    'type': type, 'content': content, 'tempId': tempId,
  };
}
