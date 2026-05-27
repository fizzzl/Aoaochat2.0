// chat_app/lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'home_screen.dart';
import 'auth_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final loggedIn = await ApiService.loadSession();
    if (!mounted) return;
    if (loggedIn) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) {
            final s = SocketService();
            s.connect();
            return s;
          },
          child: const HomeScreen(),
        ),
      ), (_) => false);
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(color: Color(0xFF2563EB))),
  );
}
