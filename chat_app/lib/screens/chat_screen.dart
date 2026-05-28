// chat_app/lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../services/socket_service.dart';
import '../services/api_service.dart';
import '../config.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final int conversationId;
  final String convName;
  final int? otherUserId;
  const ChatScreen({super.key, required this.conversationId, required this.convName, this.otherUserId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _shouldAutoScroll = true;

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
    _shouldAutoScroll = true;
    _scrollToBottom();
  }

  String _formatMsgTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1080);
    if (image == null) return;

    final uri = Uri.parse('${AppConfig.serverUrl}/api/upload');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer ${ApiService.token}';
    request.files.add(await http.MultipartFile.fromPath('file', image.path));

    final response = await request.send();
    final body = await response.stream.bytesToString();
    final data = _parseJson(body);

    if (data != null && data['code'] == 0 && data['data'] != null) {
      final url = data['data']['url'];
      context.read<SocketService>().sendMessage(
        conversationId: widget.conversationId, content: url, type: 'image');
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片上传失败'), behavior: SnackBarBehavior.floating));
    }
  }

  Map<String, dynamic>? _parseJson(String s) {
    try { return jsonDecode(s) as Map<String, dynamic>; } catch (_) { return null; }
  }

  void _startCall(String type) {
    final otherId = widget.otherUserId;
    if (otherId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法获取对方信息'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    context.read<SocketService>().startCall(calleeId: otherId, type: type);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CallScreen(
        calleeId: otherId,
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
              if (_shouldAutoScroll) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                  _shouldAutoScroll = false;
                });
              }
              return ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final msg = msgs[i];
                  final isMe = msg.senderId == ApiService.userId;
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
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!isMe) ...[
                          CircleAvatar(radius: 14, backgroundColor: const Color(0xFFDBE1FF),
                            child: Text(widget.convName.isNotEmpty ? widget.convName[0] : '?', style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB)))),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe ? const Color(0xFF2563EB) : const Color(0xFFDCE9FF),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isMe ? 16 : 2),
                                bottomRight: Radius.circular(isMe ? 2 : 16),
                              ),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              if (msg.type == 'image')
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    '${AppConfig.serverUrl}${msg.content}',
                                    width: 200, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 60, color: Colors.white54),
                                  ),
                                )
                              else
                                Text(msg.content, style: TextStyle(fontSize: 15, color: isMe ? Colors.white : const Color(0xFF0B1C30))),
                              const SizedBox(height: 4),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(_formatMsgTime(msg.createdAt),
                                  style: TextStyle(fontSize: 10, color: isMe ? Colors.white54 : const Color(0xFF737686))),
                                if (isMe) ...[
                                  const SizedBox(width: 4),
                                  Icon(msg.isRead ? Icons.done_all : Icons.done, size: 14,
                                    color: msg.isRead ? Colors.white : Colors.white54),
                                ],
                              ]),
                            ]),
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
            IconButton(
              icon: const Icon(Icons.image_outlined, color: Color(0xFF2563EB), size: 24),
              onPressed: _pickAndSendImage,
              splashRadius: 18,
            ),
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
