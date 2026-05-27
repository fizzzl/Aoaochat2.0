// chat_app/lib/screens/conversation_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
import '../models/conversation.dart';
import 'chat_screen.dart';

class ConversationListScreen extends StatelessWidget {
  const ConversationListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('嗷嗷聊天', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2563EB)))),
      body: Consumer<SocketService>(
        builder: (_, socket, __) {
          final convs = socket.conversations;
          if (!socket.connected) {
            return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: Color(0xFF2563EB)),
              SizedBox(height: 12),
              Text('连接中...', style: TextStyle(color: Colors.grey)),
            ]));
          }
          if (convs.isEmpty) {
            return const Center(child: Text('暂无会话', style: TextStyle(color: Colors.grey)));
          }
          return ListView.builder(
            itemCount: convs.length,
            itemBuilder: (_, i) {
              final conv = convs[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFDBE1FF),
                  child: Text(conv.name ?? '?', style: const TextStyle(color: Color(0xFF2563EB))),
                ),
                title: Text(conv.name ?? '会话 ${conv.id}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(conv.lastMessage ?? '暂无消息', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: conv.unreadCount > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: const BoxDecoration(color: Color(0xFF2563EB), borderRadius: BorderRadius.all(Radius.circular(10))),
                      child: Text('${conv.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    )
                  : null,
                onTap: () {
                  socket.getHistory(conversationId: conv.id);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChatScreen(conversationId: conv.id, convName: conv.name ?? '会话'),
                  ));
                },
              );
            },
          );
        },
      ),
    );
  }
}
