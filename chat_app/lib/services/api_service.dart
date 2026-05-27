// chat_app/lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class ApiService {
  static String? _token;
  static String? _refreshToken;
  static int? userId;
  static String? username;
  static String? displayName;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    _refreshToken = prefs.getString('refreshToken');
    userId = prefs.getInt('userId');
    username = prefs.getString('username');
    displayName = prefs.getString('displayName');
  }

  static Future<void> saveSession(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    _token = data['accessToken'];
    _refreshToken = data['refreshToken'];
    userId = data['user']['id'];
    username = data['user']['username'];
    displayName = data['user']['displayName'];
    await prefs.setString('token', _token!);
    await prefs.setString('refreshToken', _refreshToken!);
    await prefs.setInt('userId', userId!);
    await prefs.setString('username', username!);
    await prefs.setString('displayName', displayName ?? '');
  }

  static Future<bool> loadSession() async {
    await init();
    return _token != null;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _token = null; _refreshToken = null;
    userId = null; username = null; displayName = null;
  }

  static String? get token => _token;

  static Future<Map<String, dynamic>> _request(
    String method, String path, {Map<String, dynamic>? body}
  ) async {
    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

    final uri = Uri.parse('${AppConfig.serverUrl}$path');
    http.Response response;

    switch (method) {
      case 'GET':
        response = await http.get(uri, headers: headers);
        break;
      case 'POST':
        response = await http.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'PUT':
        response = await http.put(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: headers);
        break;
      default:
        throw Exception('Unsupported method');
    }

    final data = jsonDecode(response.body);
    if (response.statusCode == 401 && _refreshToken != null) {
      // 尝试刷新 token
      final refreshRes = await http.post(
        Uri.parse('${AppConfig.serverUrl}/api/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': _refreshToken}),
      );
      if (refreshRes.statusCode == 200) {
        final refreshData = jsonDecode(refreshRes.body);
        _token = refreshData['data']['accessToken'];
        _refreshToken = refreshData['data']['refreshToken'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', _token!);
        await prefs.setString('refreshToken', _refreshToken!);
        return _request(method, path, body: body);
      } else {
        await logout();
      }
    }
    return data;
  }

  static Future<Map<String, dynamic>> get(String path) => _request('GET', path);
  static Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) => _request('POST', path, body: body);
  static Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? body}) => _request('PUT', path, body: body);
  static Future<Map<String, dynamic>> delete(String path) => _request('DELETE', path);
}
