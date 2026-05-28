// chat_app/lib/screens/conversation_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
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
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off, size: 48, color: Color(0xFF2563EB)),
              const SizedBox(height: 12),
              const Text('连接断开', style: TextStyle(color: Colors.grey, fontSize: 15)),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => socket.connect(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新连接'),
              ),
            ]));
          }
          if (convs.isEmpty) {
            return const Center(child: Text('暂无会话', style: TextStyle(color: Colors.grey)));
          }
          return ListView.builder(
            itemCount: convs.length,
            itemBuilder: (_, i) {
              final conv = convs[i];
              final isOnline = conv.otherUserId != null &&
                socket.onlineUsers.any((u) => u.id == conv.otherUserId);
              return ListTile(
                leading: Stack(children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFDBE1FF),
                    child: Text((conv.displayName ?? conv.name ?? '?')[0], style: const TextStyle(color: Color(0xFF2563EB))),
                  ),
                  if (isOnline)
                    Positioned(bottom: 0, right: 0, child: Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(color: const Color(0xFF22C55E), shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2)),
                    )),
                ]),
                title: Text(conv.displayName ?? conv.name ?? '会话 ${conv.id}', style: const TextStyle(fontWeight: FontWeight.w600)),
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
                    builder: (_) => ChangeNotifierProvider<SocketService>.value(
                      value: socket,
                      child: ChatScreen(
                        conversationId: conv.id,
                        convName: conv.displayName ?? conv.name ?? '会话',
                        otherUserId: conv.otherUserId,
                      ),
                    ),
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
