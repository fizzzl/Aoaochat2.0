// chat_app/lib/screens/conversation_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
import '../services/api_service.dart';
import '../models/conversation.dart';
import '../utils/time_format.dart';
import 'chat_screen.dart';

class ConversationListScreen extends StatefulWidget {
  final VoidCallback? onAddFriend;
  const ConversationListScreen({super.key, this.onAddFriend});
  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final Set<int> _pinnedIds = {};

  void _togglePin(int convId) {
    setState(() {
      if (_pinnedIds.contains(convId)) _pinnedIds.remove(convId);
      else _pinnedIds.add(convId);
    });
  }

  Future<void> _deleteConv(int convId) async {
    await ApiService.delete('/api/conversations/$convId');
    if (mounted) {
      context.read<SocketService>().loadConversations();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFDBE1FF),
            child: Text(
              (ApiService.displayName ?? '?')[0].toUpperCase(),
              style: const TextStyle(fontSize: 14, color: Color(0xFF2563EB)),
            ),
          ),
        ),
        title: const Text('嗷嗷聊天', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: widget.onAddFriend,
          ),
        ],
      ),
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
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.chat_bubble_outline, size: 56, color: Color(0x302563EB)),
              const SizedBox(height: 12),
              const Text('暂无会话', style: TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: widget.onAddFriend,
                child: const Text('去搜索添加好友吧',
                  style: TextStyle(color: Color(0xFF2563EB), fontSize: 13)),
              ),
            ]));
          }

          // 排序：置顶 > 按时间倒序
          final sorted = List<Conversation>.from(convs)
            ..sort((a, b) {
              final aPin = _pinnedIds.contains(a.id);
              final bPin = _pinnedIds.contains(b.id);
              if (aPin != bPin) return aPin ? -1 : 1;
              return (b.lastMessageTime?.millisecondsSinceEpoch ?? 0)
                  .compareTo(a.lastMessageTime?.millisecondsSinceEpoch ?? 0);
            });

          return RefreshIndicator(
            onRefresh: () => socket.loadConversations(),
            child: ListView.builder(
              itemCount: sorted.length,
              itemBuilder: (_, i) {
                final conv = sorted[i];
                final pinned = _pinnedIds.contains(conv.id);
                final isOnline = conv.otherUserId != null &&
                    socket.onlineUsers.any((u) => u.id == conv.otherUserId);

                return Slidable(
                  endActionPane: ActionPane(
                    motion: const BehindMotion(),
                    children: [
                      SlidableAction(
                        onPressed: (_) => _togglePin(conv.id),
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
                        label: pinned ? '取消置顶' : '置顶',
                      ),
                      SlidableAction(
                        onPressed: (_) => _deleteConv(conv.id),
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        icon: Icons.delete_outline,
                        label: '删除',
                      ),
                    ],
                  ),
                  child: ListTile(
                    leading: Stack(children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFFDBE1FF),
                        child: Text(
                          (conv.displayName ?? conv.name ?? '?')[0],
                          style: const TextStyle(color: Color(0xFF2563EB)),
                        ),
                      ),
                      if (isOnline)
                        Positioned(bottom: 0, right: 0, child: Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E), shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2)),
                        )),
                    ]),
                    title: Text(
                      '${pinned ? '📌 ' : ''}${conv.displayName ?? conv.name ?? '会话 ${conv.id}'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Row(children: [
                      Expanded(
                        child: Text(conv.lastMessage ?? '暂无消息',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF737686))),
                      ),
                      const SizedBox(width: 4),
                      Text(formatConversationTime(conv.lastMessageTime),
                        style: const TextStyle(fontSize: 11, color: Color(0xFFA0A3B1))),
                    ]),
                    trailing: conv.unreadCount > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: const BoxDecoration(
                            color: Color(0xFF2563EB),
                            borderRadius: BorderRadius.all(Radius.circular(10))),
                          child: Text('${conv.unreadCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
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
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
