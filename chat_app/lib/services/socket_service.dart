// chat_app/lib/services/socket_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import 'api_service.dart';

class SocketService extends ChangeNotifier {
  io.Socket? _socket;
  bool _connected = false;
  final List<User> _onlineUsers = [];
  final List<Conversation> _conversations = [];
  final Map<int, List<Message>> _messages = {};
  User? _chatPartner;
  Timer? _heartbeat;

  bool get connected => _connected;
  List<User> get onlineUsers => _onlineUsers;
  List<Conversation> get conversations => _conversations;
  Map<int, List<Message>> get messages => _messages;
  User? get chatPartner => _chatPartner;

  List<Message> getMessages(int conversationId) => _messages[conversationId] ?? [];

  void clear() {
    _onlineUsers.clear();
    _conversations.clear();
    _messages.clear();
    _typingConversations.clear();
    _connected = false;
    notifyListeners();
  }

  void connect() {
    final token = ApiService.token;
    if (token == null) return;
    clear();
    if (_socket != null) disconnect();

    // 加时间戳参数防止 Socket.IO 复用传输层
    final url = '${AppConfig.serverUrl}?_=${DateTime.now().millisecondsSinceEpoch}';
    _socket = io.io(url, {
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
      'reconnectionAttempts': 999,
      'auth': {'token': token},
    });

    _socket!.onConnect((_) {
      _connected = true;
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      _connected = false;
      notifyListeners();
    });

    _socket!.onReconnect((_) {
      _connected = true;
      notifyListeners();
    });

    _socket!.on('online:update', (data) {
      _onlineUsers.clear();
      for (final u in data['users'] ?? []) {
        _onlineUsers.add(User.fromJson(u));
      }
      notifyListeners();
    });

    _socket!.on('conversation:list', (data) {
      _conversations.clear();
      for (final c in data['conversations'] ?? []) {
        _conversations.add(Conversation.fromJson(c));
      }
      notifyListeners();
    });

    _socket!.on('message:new', (data) {
      final msg = Message.fromJson(data);
      _messages.putIfAbsent(msg.conversationId, () => []).add(msg);
      // Refresh conversation list
      _socket!.emit('conversation:list');
      notifyListeners();
    });

    _socket!.on('message:sent', (data) {
      final msg = Message.fromJson(data);
      _messages.putIfAbsent(msg.conversationId, () => []).add(msg);
      notifyListeners();
    });

    _socket!.on('message:recalled', (data) {
      final convId = data['conversationId'] as int;
      final msgId = data['messageId'] as int;
      final msgs = _messages[convId];
      if (msgs != null) {
        final idx = msgs.indexWhere((m) => m.id == msgId);
        if (idx >= 0) {
          msgs[idx] = Message(
            id: msgs[idx].id,
            conversationId: msgs[idx].conversationId,
            senderId: msgs[idx].senderId,
            content: '消息已撤回',
            createdAt: msgs[idx].createdAt,
            deletedAt: DateTime.now(),
          );
          notifyListeners();
        }
      }
    });

    _socket!.on('conversation:history', (data) {
      final convId = data['conversationId'] as int;
      final msgs = (data['messages'] as List).map((m) => Message.fromJson(m)).toList();
      _messages[convId] = msgs;
      notifyListeners();
    });

    _socket!.on('message:read_ack', (data) {
      final convId = data['conversationId'] as int;
      final msgs = _messages[convId];
      if (msgs != null) {
        for (int i = 0; i < msgs.length; i++) {
          if (msgs[i].readAt == null) {
            msgs[i] = Message(
              id: msgs[i].id, conversationId: msgs[i].conversationId,
              senderId: msgs[i].senderId, content: msgs[i].content,
              createdAt: msgs[i].createdAt,
              senderDisplayName: msgs[i].senderDisplayName,
              readAt: DateTime.now(),
            );
          }
        }
        notifyListeners();
      }
    });

    _socket!.on('typing:update', (data) {
      final convId = data['conversationId'] as int? ?? 0;
      _typingConversations.add(convId);
      notifyListeners();
      Future.delayed(const Duration(seconds: 3), () {
        _typingConversations.remove(convId);
        notifyListeners();
      });
    });

    _socket!.on('call:incoming', _onCallIncoming);
    _socket!.on('call:accepted', _onCallAccepted);
    _socket!.on('call:rejected', _onCallRejected);
    _socket!.on('call:ended', _onCallEnded);
    _socket!.on('call:signal', _onCallSignal);

    _socket!.on('friend:accepted', (data) {
      _socket!.emit('conversation:list');
      notifyListeners();
    });

    _socket!.connect();

    // 心跳（取消旧的心跳）
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      _socket?.emit('ping');
    });
  }

  void emitConversationList() {
    _socket?.emit('conversation:list');
  }

  /// 通过 REST API 加载会话列表（不依赖 WebSocket，防止串号）
  Future<void> loadConversations() async {
    try {
      final data = await ApiService.get('/api/conversations');
      if (data['code'] == 0 && data['data'] != null) {
        _conversations.clear();
        for (final c in data['data']) {
          _conversations.add(Conversation.fromJson(c));
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  void sendMessage({required int conversationId, required String content, String type = 'text'}) {
    _socket?.emit('message:send', {
      'conversationId': conversationId,
      'content': content,
      'type': type,
    });
  }

  void readMessages(int conversationId) {
    _socket?.emit('message:read', {'conversationId': conversationId});
  }

  void removeLocalMessage(int convId, int msgId) {
    _messages[convId]?.removeWhere((m) => m.id == msgId);
    notifyListeners();
  }

  void recallMessage(int messageId) {
    _socket?.emit('message:recall', {'messageId': messageId});
  }

  void getHistory({required int conversationId, int? cursor}) {
    _socket?.emit('conversation:history', {
      'conversationId': conversationId,
      if (cursor != null) 'cursor': cursor,
    });
  }

  void setChatPartner(User user) {
    _chatPartner = user;
    getHistory(conversationId: user.id);
    notifyListeners();
  }

  void searchUsers(String keyword) {
    _socket?.emit('search_users', {'keyword': keyword});
  }

  void addFriend(int friendId) {
    _socket?.emit('friend:add', {'friendId': friendId});
  }

  void acceptFriend(int friendId) {
    _socket?.emit('friend:accept', {'friendId': friendId});
  }

  void removeFriend(int friendId) {
    _socket?.emit('friend:remove', {'friendId': friendId});
  }

  // 通话
  void startCall({required int calleeId, String type = 'voice'}) {
    _socket?.emit('call:start', {'calleeId': calleeId, 'type': type});
  }

  void acceptCall(String roomId) {
    _socket?.emit('call:accept', {'roomId': roomId});
  }

  void rejectCall(String roomId) {
    _socket?.emit('call:reject', {'roomId': roomId});
  }

  void endCall() {
    _socket?.emit('call:end');
  }

  void sendSignal({required int toUserId, required Map<String, dynamic> signal}) {
    _socket?.emit('call:signal', {'toUserId': toUserId, 'signal': signal});
  }

  // 正在输入
  final Set<int> _typingConversations = {};

  void sendTyping(int conversationId) {
    _socket?.emit('conversation:typing', {'conversationId': conversationId});
  }

  bool isOtherTyping(int conversationId) => _typingConversations.contains(conversationId);

  // Callbacks for call events — overridden by CallScreen
  Function(Map<String, dynamic>)? onCallIncoming;
  Function(Map<String, dynamic>)? onCallAccepted;
  Function(Map<String, dynamic>)? onCallRejected;
  Function(Map<String, dynamic>)? onCallEnded;
  Function(Map<String, dynamic>)? onCallSignal;

  void _onCallIncoming(dynamic data) => onCallIncoming?.call(data);
  void _onCallAccepted(dynamic data) => onCallAccepted?.call(data);
  void _onCallRejected(dynamic data) => onCallRejected?.call(data);
  void _onCallEnded(dynamic data) => onCallEnded?.call(data);
  void _onCallSignal(dynamic data) => onCallSignal?.call(data);

  void disconnect() {
    if (_socket == null) return;
    _heartbeat?.cancel();
    _heartbeat = null;
    _socket!.disconnect();
    _socket!.dispose();
    _socket = null;
    _connected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
