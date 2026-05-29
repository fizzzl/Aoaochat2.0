// chat_app/lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../config.dart';
import 'profile_screen.dart';
import 'auth_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final name = ApiService.displayName ?? ApiService.username ?? '';
    final username = ApiService.username ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(children: [
        const SizedBox(height: 8),
        // Profile card
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFFDBE1FF),
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 24, color: Color(0xFF2563EB))),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('@$username', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                ])),
                const Icon(Icons.chevron_right, color: Color(0xFFC3C6D7)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // About section
        const Padding(padding: EdgeInsets.only(left: 20, bottom: 8),
          child: Text('其他', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF737686)))),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.info_outline, color: Color(0xFF2563EB)),
              title: const Text('版本'),
              trailing: Text('v${AppConfig.appVersion}', style: const TextStyle(color: Colors.grey)),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('退出登录', style: TextStyle(color: Colors.red)),
              onTap: () => _showLogoutDialog(context),
            ),
          ]),
        ),
      ]),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('退出登录'),
      content: const Text('确定退出当前账号吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(onPressed: () async {
          Navigator.pop(ctx);
          final socket = context.read<SocketService>();
          socket.disconnect();
          try { await ApiService.post('/api/auth/logout', body: {'refreshToken': ApiService.refreshToken}); } catch (_) {}
          await ApiService.logout();
          if (!context.mounted) return;
          Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
        }, child: const Text('退出', style: TextStyle(color: Colors.red))),
      ],
    ));
  }
}
