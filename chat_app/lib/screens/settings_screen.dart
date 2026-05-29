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
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(ApiService.displayName ?? ApiService.username ?? '未登录'),
            subtitle: Text('@${ApiService.username ?? ''}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))),
          const Divider(),
          ListTile(leading: const Icon(Icons.info_outline), title: const Text('版本'), subtitle: Text('v${AppConfig.appVersion}')),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('退出登录', style: TextStyle(color: Colors.red)),
            onTap: () async {
              final socket = context.read<SocketService>();
              socket.disconnect();
              await ApiService.logout();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(context,
                MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
            },
          ),
        ],
      ),
    );
  }
}
