import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/user.dart';

class UserDetailScreen extends StatefulWidget {
  final int userId;
  final String? displayName;
  final String? username;
  const UserDetailScreen({super.key, required this.userId, this.displayName, this.username});
  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  Map<String, dynamic>? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ApiService.get('/api/users/${widget.userId}/profile');
    if (data['code'] == 0 && mounted) {
      setState(() { _user = data['data']; _loading = false; });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _user?['display_name']?.toString() ?? widget.displayName ?? '用户';
    final username = _user?['username']?.toString() ?? widget.username ?? '';
    final online = _user?['last_seen_at'] != null;
    return Scaffold(
      appBar: AppBar(title: const Text('用户详情')),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(20), children: [
            const SizedBox(height: 20),
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundColor: const Color(0xFFDBE1FF),
                child: Text(name[0].toUpperCase(),
                  style: const TextStyle(fontSize: 32, color: Color(0xFF2563EB))),
              ),
            ),
            const SizedBox(height: 16),
            Center(child: Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
            const SizedBox(height: 4),
            Center(child: Text('@$username', style: const TextStyle(fontSize: 14, color: Colors.grey))),
            const SizedBox(height: 8),
            Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 10, color: online ? const Color(0xFF22C55E) : Colors.grey),
              const SizedBox(width: 4),
              Text(online ? '在线' : '离线', style: TextStyle(fontSize: 13, color: online ? const Color(0xFF22C55E) : Colors.grey)),
            ])),
          ]),
    );
  }
}
