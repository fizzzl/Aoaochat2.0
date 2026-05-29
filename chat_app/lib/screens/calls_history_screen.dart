// chat_app/lib/screens/calls_history_screen.dart
import 'package:flutter/material.dart';
import '../models/call.dart';
import '../services/api_service.dart';

class CallsHistoryScreen extends StatelessWidget {
  final List<Call>? calls;
  const CallsHistoryScreen({super.key, this.calls});

  String _otherName(Call c) {
    final myId = ApiService.userId;
    if (myId == null) return c.otherPartyName;
    return (c.callerId == myId) ? (c.calleeName ?? '未知') : (c.callerName ?? '未知');
  }

  Widget _statusIcon(Call c) {
    final isIncoming = ApiService.userId != null && c.calleeId == ApiService.userId;
    if (c.status == 'missed' || c.status == 'cancelled') {
      return Icon(isIncoming ? Icons.call_missed : Icons.call_missed_outgoing,
        color: Colors.red, size: 22);
    }
    return Icon(isIncoming ? Icons.call_received : Icons.call_made,
      color: const Color(0xFF2563EB), size: 22);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通话记录')),
      body: calls == null || calls!.isEmpty
        ? Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.call_outlined, size: 56, color: const Color(0xFF2563EB).withValues(alpha: 0.15)),
              const SizedBox(height: 12),
              const Text('暂无通话记录', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 4),
              const Text('去聊天页发起通话吧', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          )
        : ListView.builder(
            itemCount: calls!.length,
            itemBuilder: (_, i) {
              final c = calls![i];
              final isIncoming = ApiService.userId != null && c.calleeId == ApiService.userId;
              final name = _otherName(c);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: (c.status == 'missed' || c.status == 'cancelled')
                    ? const Color(0xFFFEE2E2) : const Color(0xFFDBE1FF),
                  child: _statusIcon(c),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                subtitle: Row(children: [
                  Text(isIncoming ? '呼入 ' : '呼出 ',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  Icon(c.type == 'video' ? Icons.videocam : Icons.call,
                    size: 14, color: Colors.grey),
                  if (c.durationText.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(c.durationText, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ]),
                trailing: Text(
                  c.status == 'answered' ? c.durationText : (c.status == 'missed' ? '未接' : '已取消'),
                  style: TextStyle(
                    fontSize: 12,
                    color: c.status == 'missed' ? Colors.red : Colors.grey,
                  ),
                ),
              );
            },
          ),
    );
  }
}
