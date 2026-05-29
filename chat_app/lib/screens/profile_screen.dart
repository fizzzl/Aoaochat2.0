import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../config.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final name = ApiService.displayName ?? ApiService.username ?? '';
    final username = ApiService.username ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('我的资料')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 48,
            backgroundColor: const Color(0xFFDBE1FF),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 32, color: Color(0xFF2563EB))),
          ),
          const SizedBox(height: 16),
          Center(child: Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
          const SizedBox(height: 4),
          Center(child: Text('@$username', style: const TextStyle(fontSize: 14, color: Colors.grey))),
          const SizedBox(height: 32),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.person_outline, color: Color(0xFF2563EB)),
                title: const Text('显示名称', style: TextStyle(fontSize: 14)),
                subtitle: Text(name, style: const TextStyle(fontSize: 16)),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.phone_outlined, color: Color(0xFF2563EB)),
                title: const Text('应用版本', style: TextStyle(fontSize: 14)),
                subtitle: Text('v${AppConfig.appVersion}', style: const TextStyle(fontSize: 16)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('退出登录', style: TextStyle(color: Colors.red)),
              onTap: () => _logout(context),
            ),
          ),
        ],
      ),
    );
  }

  void _logout(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('退出登录'), content: const Text('确定退出吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(onPressed: () async {
          Navigator.pop(ctx);
          await ApiService.logout();
          if (context.mounted) {
            Navigator.pushAndRemoveUntil(context,
              MaterialPageRoute(builder: (_) => const Scaffold(
                body: Center(child: Text('已退出', style: TextStyle(color: Colors.grey))),
              )), (_) => false);
          }
        }, child: const Text('退出', style: TextStyle(color: Colors.red))),
      ],
    ));
  }
}
