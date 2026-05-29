// chat_app/lib/screens/auth_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _usernameCtrl.dispose(); _passwordCtrl.dispose();
    _displayNameCtrl.dispose(); _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _error = null; _loading = true; });
    try {
      final body = {
        'username': _usernameCtrl.text.trim(),
        'password': _passwordCtrl.text,
        if (!_isLogin) 'displayName': _displayNameCtrl.text.trim(),
        if (!_isLogin) 'phone': _phoneCtrl.text.trim(),
      };

      final path = _isLogin ? '/api/auth/login' : '/api/auth/register';
      final data = await (_isLogin
        ? ApiService.post(path, body: body)
        : ApiService.post(path, body: body));

      if (data['code'] == 0 && data['data'] != null) {
        await ApiService.saveSession(data['data']);
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) {
              final s = SocketService();
              s.connect();
              // 登录后通过 REST API 加载会话列表（不依赖 WebSocket，防止串号）
              Future.delayed(const Duration(milliseconds: 500), () {
                s.loadConversations();
              });
              return s;
            },
            child: const HomeScreen(),
          ),
        ), (_) => false);
      } else {
        setState(() => _error = data['message'] ?? '操作失败');
      }
    } catch (e) {
      setState(() => _error = '网络错误');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('💬', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text(_isLogin ? '嗷嗷聊天二代' : '创建账号',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
              ),
              const SizedBox(height: 24),
              if (!_isLogin) ...[
                TextField(controller: _displayNameCtrl, decoration: const InputDecoration(hintText: '显示名', prefixIcon: Icon(Icons.person_outline))),
                const SizedBox(height: 12),
              ],
              TextField(controller: _usernameCtrl, decoration: const InputDecoration(hintText: '用户名', prefixIcon: Icon(Icons.account_circle_outlined))),
              const SizedBox(height: 12),
              TextField(controller: _passwordCtrl, obscureText: true, decoration: const InputDecoration(hintText: '密码', prefixIcon: Icon(Icons.lock_outlined))),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: Text(_loading ? '处理中...' : (_isLogin ? '登录' : '注册')),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() { _isLogin = !_isLogin; _error = null; }),
                child: Text(_isLogin ? '还没有账号？立即注册' : '已有账号？去登录',
                  style: const TextStyle(color: Color(0xFF2563EB)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
