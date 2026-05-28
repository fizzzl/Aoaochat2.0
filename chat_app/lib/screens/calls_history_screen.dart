// chat_app/lib/screens/calls_history_screen.dart
import 'package:flutter/material.dart';
import '../models/call.dart';

class CallsHistoryScreen extends StatelessWidget {
  final List<Call>? calls;
  const CallsHistoryScreen({super.key, this.calls});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通话记录')),
      body: calls == null || calls!.isEmpty
        ? const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.call_outlined, size: 56, color: Color(0x302563EB)),
              SizedBox(height: 12),
              Text('暂无通话记录', style: TextStyle(color: Colors.grey)),
            ]),
          )
        : ListView.builder(
            itemCount: calls!.length,
            itemBuilder: (_, i) {
              final c = calls![i];
              return ListTile(
                leading: Icon(
                  c.type == 'video' ? Icons.videocam : Icons.call,
                  color: c.status == 'missed' ? Colors.red : const Color(0xFF2563EB),
                ),
                title: Text(c.type == 'video' ? '视频通话' : '语音通话'),
                subtitle: Text(c.status == 'answered' ? '已接听' : '未接听'),
              );
            },
          ),
    );
  }
}
