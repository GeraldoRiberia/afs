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
  final String _userFileName = 'afs_user_info.json';

  String get _baseUrl => BackendConfig.baseUrl;

  Future<File> get _tokenFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_tokenFileName');
  }

  Future<File> get _userFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_userFileName');
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

  Future<String?> getToken() async {
    try {
      final file = await _tokenFile;
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getCurrentUserName() async {
    try {
      final file = await _userFile;
      if (!await file.exists()) return null;
      final contents = await file.readAsString();
      final data = jsonDecode(contents);
      if (data is Map<String, dynamic>) {
        return data['full_name'] as String?;
      }
    } catch (_) {}
    return null;
  }

  Future<void> logout() async {
    try {
      final file = await _tokenFile;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    try {
      final userFile = await _userFile;
      if (await userFile.exists()) {
        await userFile.delete();
      }
    } catch (_) {}
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
      if (body is Map<String, dynamic> && body['user'] is Map<String, dynamic>) {
        await _saveUserInfo(body['user'] as Map<String, dynamic>);
      }
    } catch (_) {
      // Ignore if token or user info is not found or parsing fails
    }
  }

  Future<void> _saveUserInfo(Map<String, dynamic> user) async {
    try {
      final file = await _userFile;
      await file.writeAsString(jsonEncode(user));
    } catch (_) {
      // Ignore write failures
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
