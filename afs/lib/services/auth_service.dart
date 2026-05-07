import 'dart:convert';

import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'config.dart';

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();
  final String _tokenFileName = 'afs_jwt_token.txt';

  String get _baseUrl => BackendConfig.baseUrl;

  Future<File> get _tokenFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_tokenFileName');
  }

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
    try {
      final file = await _tokenFile;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<String?> getToken() async {
    try {
      final file = await _tokenFile;
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (_) {}
    return null;
  }

  Future<void> enrollFace(String videoPath) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      throw const AuthException('Not logged in');
    }

    final uri = Uri.parse('$_baseUrl/api/enroll_face');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(await http.MultipartFile.fromPath('video', videoPath));

    final response = await http.Response.fromStream(await request.send());
    _throwIfFailed(response);
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> _saveTokenFromResponse(http.Response response) async {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['token'] is String) {
        final file = await _tokenFile;
        await file.writeAsString(body['token'] as String);
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
