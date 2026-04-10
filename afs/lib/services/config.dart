import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BackendConfig {
  static String baseUrl = 'https://arnavam-afs-backend.hf.space';
  static String wsUrl = 'wss://arnavam-afs-backend.hf.space/ws';

  static Future<void> init() async {
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final localBaseUrl = isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';
    
    try {
      // Try to connect to localhost:8000
      final response = await http.get(Uri.parse(localBaseUrl)).timeout(const Duration(milliseconds: 1500));
      // If reachable, use localhost
      baseUrl = localBaseUrl;
      wsUrl = isAndroid ? 'ws://10.0.2.2:8000/ws' : 'ws://127.0.0.1:8000/ws';
    } catch (_) {
      // Fallback to production URL
      baseUrl = 'https://arnavam-afs-backend.hf.space';
      wsUrl = 'wss://arnavam-afs-backend.hf.space/ws';
    }
  }
}
