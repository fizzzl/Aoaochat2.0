// chat_app/lib/screens/contacts_screen.dart
import 'package:flutter/material.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('联系人')),
      body: const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.people_outline, size: 56, color: Color(0x302563EB)),
          SizedBox(height: 12),
          Text('暂无好友', style: TextStyle(color: Colors.grey)),
        ]),
      ),
    );
  }
}
