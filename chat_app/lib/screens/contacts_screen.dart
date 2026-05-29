// chat_app/lib/screens/contacts_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
import '../services/api_service.dart';
import '../models/conversation.dart';
import 'chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _requests = [];
  bool _loading = false;
  String _statusMsg = '';

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  void initState() { super.initState(); _loadFriends(); }

  Future<void> _loadFriends() async {
    final data = await ApiService.get('/api/friends');
    if (data['code'] == 0) setState(() => _friends = List<Map<String, dynamic>>.from(data['data'] ?? []));
    final reqData = await ApiService.get('/api/friends/requests');
    if (reqData['code'] == 0) setState(() => _requests = List<Map<String, dynamic>>.from(reqData['data'] ?? []));
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) { setState(() { _searchResults = []; _statusMsg = ''; }); return; }
    setState(() => _loading = true);
    final data = await ApiService.get('/api/users/search?q=${Uri.encodeComponent(q.trim())}');
    if (data['code'] == 0) {
      setState(() { _searchResults = List<Map<String, dynamic>>.from(data['data'] ?? []); _statusMsg = _searchResults.isEmpty ? '未找到用户' : ''; });
    }
    setState(() => _loading = false);
  }

  bool _isFriend(int id) => _friends.any((f) => f['id'] == id);

  void _addFriend(int friendId, String name) {
    context.read<SocketService>().addFriend(friendId);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已发送好友请求给 $name'), behavior: SnackBarBehavior.floating));
  }

  void _removeFriend(int friendId) {
    context.read<SocketService>().removeFriend(friendId);
    _loadFriends();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除好友'), behavior: SnackBarBehavior.floating));
  }

  void _startChat(Map<String, dynamic> friend) async {
    final res = await ApiService.post('/api/conversations', body: {'userId': friend['id']});
    if (res['code'] == 0 && res['data'] != null) {
      final convId = res['data']['id'] as int;
      final name = friend['display_name']?.toString() ?? friend['displayName']?.toString() ?? '';
      final socket = context.read<SocketService>();
      socket.getHistory(conversationId: convId);
      socket.loadConversations(); // 刷新会话列表
      if (mounted) Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider<SocketService>.value(
          value: socket,
          child: ChatScreen(conversationId: convId, convName: name, otherUserId: friend['id'] as int),
        ),
      ));
    }
  }

  void _acceptFriend(int friendId) async {
    context.read<SocketService>().acceptFriend(friendId);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已接受好友请求'), behavior: SnackBarBehavior.floating));
    await Future.delayed(const Duration(milliseconds: 500));
    _loadFriends();
  }

  bool _isOnline(Map<String, dynamic> friend, Set<int> onlineIds) {
    return onlineIds.contains(friend['id']);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('联系人')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索用户名或昵称',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); _search(''); })
                : null,
              filled: true, fillColor: const Color(0xFFEFF4FF),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: _search,
          ),
        ),
        Expanded(
          child: Consumer<SocketService>(
            builder: (_, socket, __) {
              final onlineIds = socket.onlineUsers.map((u) => u.id).toSet();

              // Sort friends: online first, then by name
              final sortedFriends = List<Map<String, dynamic>>.from(_friends)
                ..sort((a, b) {
                  final aOnline = _isOnline(a, onlineIds);
                  final bOnline = _isOnline(b, onlineIds);
                  if (aOnline != bOnline) return aOnline ? -1 : 1;
                  return (a['display_name']?.toString() ?? '').compareTo(b['display_name']?.toString() ?? '');
                });

              return ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                if (_searchCtrl.text.isNotEmpty) ...[
                  if (_loading)
                    const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                  else if (_statusMsg.isNotEmpty)
                    Padding(padding: const EdgeInsets.all(16), child: Text(_statusMsg, style: const TextStyle(color: Colors.grey)))
                  else
                    ..._searchResults.map((u) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFDBE1FF),
                        child: Text((u['display_name']?.toString() ?? '?')[0], style: const TextStyle(color: Color(0xFF2563EB)))),
                      title: Text(u['display_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('@${u['username']}', style: const TextStyle(fontSize: 12)),
                      trailing: _isFriend(u['id'])
                        ? const Text('已是好友', style: TextStyle(color: Colors.grey, fontSize: 12))
                        : ElevatedButton(
                            onPressed: () => _addFriend(u['id'] as int, u['display_name']?.toString() ?? ''),
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 32)),
                            child: const Text('添加')),
                    )),
                  const Divider(),
                ],
                if (_requests.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text('好友请求 (${_requests.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF737686)))),
                  ..._requests.map((r) => ListTile(
                    leading: CircleAvatar(backgroundColor: const Color(0xFFDBE1FF),
                      child: Text((r['display_name']?.toString() ?? '?')[0], style: const TextStyle(color: Color(0xFF2563EB)))),
                    title: Text(r['display_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('@${r['username']}', style: const TextStyle(fontSize: 12)),
                    trailing: ElevatedButton(
                      onPressed: () => _acceptFriend(r['id'] as int),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 32)),
                      child: const Text('接受')),
                  )),
                  const Divider(),
                ],
                if (sortedFriends.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text('我的好友 (${sortedFriends.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF737686)))),
                  ...sortedFriends.map((f) {
                    final online = _isOnline(f, onlineIds);
                    return Slidable(
                      endActionPane: ActionPane(motion: const BehindMotion(), children: [
                        SlidableAction(
                          onPressed: (_) => _removeFriend(f['id'] as int),
                          backgroundColor: Colors.red, foregroundColor: Colors.white,
                          icon: Icons.person_remove_outlined, label: '删除'),
                      ]),
                      child: ListTile(
                        onTap: () => _startChat(f),
                        leading: Stack(children: [
                          CircleAvatar(backgroundColor: const Color(0xFFDBE1FF),
                            child: Text((f['display_name']?.toString() ?? '?')[0], style: const TextStyle(color: Color(0xFF2563EB)))),
                          if (online) Positioned(bottom: 0, right: 0, child: Container(
                            width: 12, height: 12,
                            decoration: BoxDecoration(color: const Color(0xFF22C55E), shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2)))),
                        ]),
                        title: Row(children: [
                          Text(f['display_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (online) ...[const SizedBox(width: 6), const Text('在线', style: TextStyle(fontSize: 11, color: Color(0xFF22C55E)))],
                        ]),
                        subtitle: Text('@${f['username']}', style: const TextStyle(fontSize: 12)),
                      ),
                    );
                  }),
                ] else if (_searchCtrl.text.isEmpty && _requests.isEmpty)
                  const Padding(padding: EdgeInsets.all(32),
                    child: Center(child: Text('暂无好友，搜索添加吧', style: TextStyle(color: Colors.grey)))),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
