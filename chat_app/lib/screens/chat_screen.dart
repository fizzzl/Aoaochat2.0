// chat_app/lib/screens/chat_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../services/socket_service.dart';
import '../services/api_service.dart';
import '../models/message.dart';
import '../config.dart';
import 'image_preview_screen.dart';
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
  bool _otherTyping = false;
  Timer? _typingTimer;

  static const _emojis = ['😀','😂','🤣','😊','😍','🤩','😎','🥳','😢','😡','👍','👎','❤️','🔥','⭐','🎉','💯','✅','❌','🎨','🍕','☕','🚀','💡','📎','🔒','👋','🤝','🙏','💪'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SocketService>().readMessages(widget.conversationId);
    });
    // 注册 typing 回调
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final socket = context.read<SocketService>();
      final prev = socket.onCallIncoming;
      // Wrap existing callback
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose(); _scrollCtrl.dispose();
    _typingTimer?.cancel();
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

  void _onTextChanged(String v) {
    final socket = context.read<SocketService>();
    socket.sendTyping(widget.conversationId);
  }

  String _formatMsgTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateHead(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return '今天';
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) return '昨天';
    return '${d.month}月${d.day}日';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _showEmojiPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 32, height: 4,
            decoration: BoxDecoration(color: const Color(0xFFC3C6D7), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Wrap(spacing: 4, runSpacing: 4,
            children: _emojis.map((e) => GestureDetector(
              onTap: () {
                _msgCtrl.text += e;
                _msgCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _msgCtrl.text.length));
                Navigator.pop(context);
              },
              child: Container(width: 44, height: 44, alignment: Alignment.center,
                child: Text(e, style: const TextStyle(fontSize: 24))),
            )).toList(),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  void _recallMessage(int msgId) {
    context.read<SocketService>().recallMessage(msgId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('消息已撤回'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 1)));
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1080);
    if (image == null) return;
    try {
      final bytes = await image.readAsBytes();
      final uri = Uri.parse('${AppConfig.serverUrl}/api/upload');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer ${ApiService.token}';
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'image.jpg', contentType: MediaType('image', 'jpeg')));
      final streamed = await request.send().timeout(const Duration(seconds: 15));
      final body = await streamed.stream.bytesToString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (data['code'] == 0 && data['data'] != null) {
        final url = data['data']['url'];
        context.read<SocketService>().sendMessage(conversationId: widget.conversationId, content: url, type: 'image');
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? '上传失败(${data['code']})'),
            behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败: ${e.toString().substring(0, e.toString().length.clamp(0, 80))}'),
          behavior: SnackBarBehavior.floating));
    }
  }

  Widget _buildMessageBubble(Message msg) {
    final isMe = msg.senderId == ApiService.userId;
    if (msg.isRecalled) {
      return const Center(child: Padding(padding: EdgeInsets.all(8),
        child: Text('消息已撤回', style: TextStyle(color: Colors.grey, fontSize: 12))));
    }
    return GestureDetector(
      onLongPress: isMe ? () => _showRecallDialog(msg) : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) ...[
              CircleAvatar(radius: 14, backgroundColor: const Color(0xFFDBE1FF),
                child: Text(widget.convName.isNotEmpty ? widget.convName[0] : '?',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB)))),
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
                    bottomLeft: Radius.circular(isMe ? 16 : 2), bottomRight: Radius.circular(isMe ? 2 : 16)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (msg.type == 'image')
                    GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ImagePreviewScreen(imageUrl: msg.content))),
                      child: ClipRRect(borderRadius: BorderRadius.circular(8),
                        child: Image.network('${AppConfig.serverUrl}${msg.content}', width: 200, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 60, color: Colors.white54)))),
                  if (msg.type != 'image')
                    Text(msg.content, style: TextStyle(fontSize: 15, color: isMe ? Colors.white : const Color(0xFF0B1C30))),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_formatMsgTime(msg.createdAt), style: TextStyle(fontSize: 10, color: isMe ? Colors.white54 : const Color(0xFF737686))),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(msg.isRead ? Icons.done_all : Icons.done, size: 14, color: msg.isRead ? Colors.white : Colors.white54),
                    ],
                  ]),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecallDialog(Message msg) {
    final diff = DateTime.now().difference(msg.createdAt).inSeconds;
    if (diff > 120) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已超过 2 分钟撤回时限'), behavior: SnackBarBehavior.floating));
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.undo, color: Color(0xFF2563EB)), title: const Text('撤回消息'),
          onTap: () { Navigator.pop(context); _recallMessage(msg.id); }),
      ])),
    );
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
                  _scrollToBottom(); _shouldAutoScroll = false;
                });
              }
              final grouped = <Widget>[];
              String? lastDate;
              for (final m in msgs) {
                final ds = _formatDateHead(m.createdAt);
                if (ds != lastDate) {
                  lastDate = ds;
                  grouped.add(Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFDCE9FF), borderRadius: BorderRadius.circular(10)),
                      child: Text(ds, style: const TextStyle(fontSize: 11, color: Color(0xFF434655)))))));
                }
                grouped.add(_buildMessageBubble(m));
              }
              return ListView(controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: grouped);
            },
          ),
        ),
        // 正在输入
        Consumer<SocketService>(
          builder: (_, socket, __) {
            final typing = socket.isOtherTyping(widget.conversationId);
            return typing
              ? Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Row(children: [
                    Text('${widget.convName} 正在输入...',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF737686))),
                    const SizedBox(width: 4),
                    const SizedBox(width: 16, height: 12, child: LinearProgressIndicator(backgroundColor: Colors.transparent)),
                  ]))
              : const SizedBox.shrink();
          },
        ),
        // Input bar
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, -1)),
          ]),
          child: SafeArea(child: Row(children: [
            IconButton(icon: const Icon(Icons.emoji_emotions_outlined, color: Color(0xFF2563EB), size: 24),
              onPressed: _showEmojiPicker, splashRadius: 18),
            IconButton(icon: const Icon(Icons.image_outlined, color: Color(0xFF2563EB), size: 22),
              onPressed: _pickAndSendImage, splashRadius: 18),
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(24)),
                child: TextField(
                  controller: _msgCtrl,
                  decoration: const InputDecoration(
                    border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    hintText: '输入消息...', hintStyle: TextStyle(color: Color(0xFF737686), fontSize: 14)),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  onChanged: (_) {
                    context.read<SocketService>().sendTyping(widget.conversationId);
                  },
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _send,
              child: Container(width: 38, height: 38,
                decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 18)),
            ),
          ])),
        ),
      ]),
    );
  }

  void _startCall(String type) {
    final otherId = widget.otherUserId;
    if (otherId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法获取对方信息'), behavior: SnackBarBehavior.floating));
      return;
    }
    final socket = context.read<SocketService>();
    socket.startCall(calleeId: otherId, type: type);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<SocketService>.value(
        value: socket,
        child: CallScreen(calleeId: otherId, calleeName: widget.convName, type: type, isIncoming: false),
      ),
    ));
  }
}
