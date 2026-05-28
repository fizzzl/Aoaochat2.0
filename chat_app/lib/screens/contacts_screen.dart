// chat_app/lib/screens/contacts_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
import '../services/api_service.dart';
import '../models/user.dart';

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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final data = await ApiService.get('/api/friends');
    if (data['code'] == 0) {
      setState(() => _friends = List<Map<String, dynamic>>.from(data['data'] ?? []));
    }
    final reqData = await ApiService.get('/api/friends/requests');
    if (reqData['code'] == 0) {
      setState(() => _requests = List<Map<String, dynamic>>.from(reqData['data'] ?? []));
    }
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _searchResults = []; _statusMsg = ''; });
      return;
    }
    setState(() => _loading = true);
    final data = await ApiService.get('/api/users/search?q=${Uri.encodeComponent(q.trim())}');
    if (data['code'] == 0) {
      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(data['data'] ?? []);
        _statusMsg = _searchResults.isEmpty ? '未找到用户' : '';
      });
    }
    setState(() => _loading = false);
  }

  Future<void> _addFriend(int friendId, String name) async {
    context.read<SocketService>().addFriend(friendId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已发送好友请求给 $name'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _acceptFriend(int friendId) async {
    context.read<SocketService>().acceptFriend(friendId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已接受好友请求'), behavior: SnackBarBehavior.floating),
    );
    await Future.delayed(const Duration(milliseconds: 500));
    _loadFriends();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('联系人')),
      body: Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索用户名或昵称添加好友',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); _search(''); })
                : null,
              filled: true,
              fillColor: const Color(0xFFEFF4FF),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: _search,
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              // Search results
              if (_searchCtrl.text.isNotEmpty) ...[
                if (_loading)
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                else if (_statusMsg.isNotEmpty)
                  Padding(padding: const EdgeInsets.all(16), child: Text(_statusMsg, style: const TextStyle(color: Colors.grey)))
                else
                  ..._searchResults.map((u) => _userTile(u, isSearchResult: true)),
                const Divider(),
              ],

              // Pending requests
              if (_requests.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 4),
                  child: Text('好友请求', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF737686))),
                ),
                ..._requests.map((r) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFDBE1FF),
                    child: Text((r['display_name']?.toString() ?? '?')[0], style: const TextStyle(color: Color(0xFF2563EB))),
                  ),
                  title: Text(r['display_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('@${r['username']}', style: const TextStyle(fontSize: 12)),
                  trailing: ElevatedButton(
                    onPressed: () => _acceptFriend(r['id'] as int),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 32)),
                    child: const Text('接受'),
                  ),
                )),
                const Divider(),
              ],

              // Friends list
              if (_friends.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 4),
                  child: Text('我的好友', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF737686))),
                ),
                ..._friends.map((f) => _userTile(f)),
              ] else if (_searchCtrl.text.isEmpty && _requests.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('暂无好友，搜索添加吧', style: TextStyle(color: Colors.grey))),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _userTile(Map<String, dynamic> u, {bool isSearchResult = false}) {
    final name = u['display_name']?.toString() ?? u['displayName']?.toString() ?? '';
    final username = u['username']?.toString() ?? '';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFDBE1FF),
        child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(color: Color(0xFF2563EB))),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('@$username', style: const TextStyle(fontSize: 12)),
      trailing: isSearchResult
        ? ElevatedButton(
            onPressed: () => _addFriend(u['id'] as int, name),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 32)),
            child: const Text('添加'),
          )
        : null,
    );
  }
}
