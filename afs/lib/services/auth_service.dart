import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();
  final _storage = const FlutterSecureStorage();
  final String _tokenKey = 'jwt_token';

    bool get _isAndroidPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  String get _baseUrl =>
      _isAndroidPlatform ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/register');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'full_name': fullName,
        'email': email,
        'password': password,
      }),
    );

    _throwIfFailed(response);
    await _saveTokenFromResponse(response);
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/login');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    _throwIfFailed(response);
    await _saveTokenFromResponse(response);
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  Future<void> _saveTokenFromResponse(http.Response response) async {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['token'] is String) {
        await _storage.write(key: _tokenKey, value: body['token'] as String);
      }
    } catch (_) {
      // Ignore if token is not found or parsing fails
    }
  }

  void _throwIfFailed(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    String fallback = 'Request failed (${response.statusCode}).';
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['detail'] is String) {
        throw AuthException(body['detail'] as String);
      }
    } catch (_) {
      // Ignore JSON parse failures and use fallback.
    }

    throw AuthException(fallback);
  }
}
