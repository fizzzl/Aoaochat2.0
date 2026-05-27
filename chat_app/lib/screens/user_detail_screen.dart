// chat_app/lib/screens/user_detail_screen.dart
import 'package:flutter/material.dart';

class UserDetailScreen extends StatelessWidget {
  const UserDetailScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('用户详情')),
    body: const Center(child: Text('用户详情', style: TextStyle(color: Colors.grey))),
  );
}
