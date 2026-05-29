// chat_app/lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
    // FCM 注册（后台静默，不阻塞启动）
    _registerFcm();

    // 验证保存的 token 是否有效（避免残留旧 token 导致串号）
    final saved = await ApiService.loadSession();
    bool valid = false;
    if (saved && ApiService.refreshToken != null) {
      try {
        final r = await ApiService.post('/api/auth/refresh', body: {'refreshToken': ApiService.refreshToken});
        if (r['code'] == 0 && r['data'] != null) {
          await ApiService.saveSession(r['data']);
          valid = true;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    if (valid) {
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
      await ApiService.logout();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
    }
  }

  Future<void> _registerFcm() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 5));
      if (fcmToken != null) {
        await ApiService.post('/api/devices', body: {
          'platform': 'android', 'pushToken': fcmToken,
        }).timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(color: Color(0xFF2563EB))),
  );
}
