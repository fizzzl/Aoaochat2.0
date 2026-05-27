// chat_app/lib/screens/calls_history_screen.dart
import 'package:flutter/material.dart';

class CallsHistoryScreen extends StatelessWidget {
  const CallsHistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通话记录')),
      body: const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.call_outlined, size: 56, color: Color(0x302563EB)),
          SizedBox(height: 12),
          Text('暂无通话记录', style: TextStyle(color: Colors.grey)),
        ]),
      ),
    );
  }
}
