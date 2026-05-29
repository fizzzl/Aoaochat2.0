// chat_app/lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../models/call.dart';
import 'conversation_list_screen.dart';
import 'calls_history_screen.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';
import 'call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  List<Call> _calls = [];

  @override
  void initState() {
    super.initState();
    _loadCalls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupCallListener();
    });
  }

  void _setupCallListener() {
    final socket = context.read<SocketService>();
    socket.onCallIncoming = (data) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider<SocketService>.value(
          value: socket,
          child: CallScreen(
            calleeId: ApiService.userId ?? 0,
            calleeName: data['callerName'] ?? '',
            type: data['type'] ?? 'voice',
            isIncoming: true,
            roomId: data['roomId'],
            callerId: data['callerId'],
            callerName: data['callerName'],
          ),
        ),
      ));
    };
  }

  Future<void> _loadCalls() async {
    final data = await ApiService.get('/api/calls');
    if (data['code'] == 0 && data['data'] != null) {
      final list = (data['data'] as List).map((c) => Call.fromJson(c)).toList();
      if (mounted) setState(() => _calls = list);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: [
        ConversationListScreen(onAddFriend: () => setState(() => _currentIndex = 2)),
        CallsHistoryScreen(calls: _calls.isEmpty ? null : _calls),
        const ContactsScreen(),
        const SettingsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          if (i == 1) _loadCalls();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: '聊天'),
          NavigationDestination(icon: Icon(Icons.call_outlined), selectedIcon: Icon(Icons.call), label: '通话'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: '联系人'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
