// chat_app/lib/screens/profile_screen.dart
import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的资料')),
    body: const Center(child: Text('个人资料', style: TextStyle(color: Colors.grey))),
  );
}
