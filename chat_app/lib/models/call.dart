// chat_app/lib/models/call.dart
class Call {
  final int id;
  final int callerId;
  final int calleeId;
  final String? callerName;
  final String? calleeName;
  final String type;
  final String roomId;
  final String status;
  final DateTime? startedAt;
  final DateTime? endedAt;

  String get otherPartyName => callerName ?? calleeName ?? '未知';
  bool get isIncoming => true; // determined by callerId vs current user
  String get durationText {
    if (startedAt == null || endedAt == null) return '';
    final secs = endedAt!.difference(startedAt!).inSeconds;
    if (secs < 60) return '${secs}秒';
    return '${secs ~/ 60}分${secs % 60}秒';
  }

  Call({
    required this.id,
    required this.callerId,
    required this.calleeId,
    this.callerName,
    this.calleeName,
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
    callerName: json['caller_name'] ?? json['callerName'],
    calleeName: json['callee_name'] ?? json['calleeName'],
    type: json['type'] ?? 'voice',
    roomId: json['room_id'] ?? json['roomId'] ?? '',
    status: json['status'] ?? 'missed',
    startedAt: json['started_at'] != null ? DateTime.tryParse(json['started_at']) : null,
    endedAt: json['ended_at'] != null ? DateTime.tryParse(json['ended_at']) : null,
  );
}
