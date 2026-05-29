// chat_app/lib/screens/calls_history_screen.dart
import 'package:flutter/material.dart';
import '../models/call.dart';
import '../services/api_service.dart';
import '../utils/time_format.dart';

class CallsHistoryScreen extends StatelessWidget {
  final List<Call>? calls;
  const CallsHistoryScreen({super.key, this.calls});

  String _otherName(Call c) {
    final myId = ApiService.userId;
    if (myId == null) return c.otherPartyName;
    return (c.callerId == myId) ? (c.calleeName ?? '未知') : (c.callerName ?? '未知');
  }

  String _callLabel(Call c) {
    final isIncoming = ApiService.userId != null && c.calleeId == ApiService.userId;
    final base = isIncoming ? '呼入' : '呼出';
    final type = c.type == 'video' ? '视频' : '语音';
    return '$type$base';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通话记录')),
      body: calls == null || calls!.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.call_outlined, size: 56, color: const Color(0xFF2563EB).withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            const Text('暂无通话记录', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            const Text('去聊天页发起通话吧', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ]))
        : ListView.builder(
            itemCount: calls!.length,
            itemBuilder: (_, i) {
              final c = calls![i];
              final isIncoming = ApiService.userId != null && c.calleeId == ApiService.userId;
              final name = _otherName(c);
              final missed = c.status == 'missed' || c.status == 'cancelled';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: missed ? const Color(0xFFFEE2E2) : const Color(0xFFDBE1FF),
                  child: Icon(
                    missed ? Icons.call_missed : (isIncoming ? Icons.call_received : Icons.call_made),
                    color: missed ? Colors.red : const Color(0xFF2563EB), size: 20),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                subtitle: Text(
                  '${_callLabel(c)} · ${c.durationText.isNotEmpty ? c.durationText : (missed ? "未接" : "")}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                trailing: Text(
                  c.endedAt != null ? formatConversationTime(c.endedAt) : '',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              );
            },
          ),
    );
  }
}
