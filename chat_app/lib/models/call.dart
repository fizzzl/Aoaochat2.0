// chat_app/lib/models/call.dart
class Call {
  final int id;
  final int callerId;
  final int calleeId;
  final String type;
  final String roomId;
  final String status;
  final DateTime? startedAt;
  final DateTime? endedAt;

  Call({
    required this.id,
    required this.callerId,
    required this.calleeId,
    this.type = 'voice',
    required this.roomId,
    this.status = 'missed',
    this.startedAt,
    this.endedAt,
  });

  factory Call.fromJson(Map<String, dynamic> json) => Call(
    id: json['id'] ?? 0,
    callerId: json['caller_id'] ?? json['callerId'] ?? 0,
    calleeId: json['callee_id'] ?? json['calleeId'] ?? 0,
    type: json['type'] ?? 'voice',
    roomId: json['room_id'] ?? json['roomId'] ?? '',
    status: json['status'] ?? 'missed',
    startedAt: json['started_at'] != null ? DateTime.tryParse(json['started_at']) : null,
    endedAt: json['ended_at'] != null ? DateTime.tryParse(json['ended_at']) : null,
  );
}
