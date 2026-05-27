// chat_app/lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
import '../models/message.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final int conversationId;
  final String convName;
  const ChatScreen({super.key, required this.conversationId, required this.convName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SocketService>().readMessages(widget.conversationId);
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose(); _scrollCtrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    context.read<SocketService>().sendMessage(conversationId: widget.conversationId, content: text);
    _msgCtrl.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _startCall(String type) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CallScreen(
        calleeId: widget.conversationId, // simplified — needs actual userId from conversation
        calleeName: widget.convName,
        type: type,
        isIncoming: false,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.convName),
        actions: [
          IconButton(icon: const Icon(Icons.call, color: Color(0xFF2563EB)), onPressed: () => _startCall('voice')),
          IconButton(icon: const Icon(Icons.videocam, color: Color(0xFF2563EB)), onPressed: () => _startCall('video')),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Consumer<SocketService>(
            builder: (_, socket, __) {
              final msgs = socket.getMessages(widget.conversationId);
              if (msgs.isEmpty) {
                return const Center(child: Text('发送第一条消息吧', style: TextStyle(color: Colors.grey)));
              }
              Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
              return ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final msg = msgs[i];
                  final isMe = msg.senderId == (socket.chatPartner?.id ?? 0);
                  if (msg.isRecalled) {
                    return const Center(child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('消息已撤回', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ));
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe ? const Color(0xFF2563EB) : const Color(0xFFDCE9FF),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isMe ? 16 : 2),
                                bottomRight: Radius.circular(isMe ? 2 : 16),
                              ),
                            ),
                            child: Text(msg.content, style: TextStyle(fontSize: 15, color: isMe ? Colors.white : const Color(0xFF0B1C30))),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        // Input bar
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, -1)),
          ]),
          child: SafeArea(child: Row(children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _msgCtrl,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    hintText: '输入消息...',
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
                child: const Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
          ])),
        ),
      ]),
    );
  }
}
