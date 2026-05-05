import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BackendConfig {
  static String baseUrl = 'https://arnavam-afs-backend.hf.space';
  static String wsUrl = 'wss://arnavam-afs-backend.hf.space/ws';
  static String soundBaseUrl = 'http://127.0.0.1:8001';

  static Future<void> init() async {
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final localBaseUrl = isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';
    final localSoundUrl = isAndroid ? 'http://10.0.2.2:8001' : 'http://127.0.0.1:8001';
    
    try {
      // Try to connect to localhost:8000
      final response = await http.get(Uri.parse(localBaseUrl)).timeout(const Duration(milliseconds: 1500));
      // If reachable, use localhost
      baseUrl = localBaseUrl;
      wsUrl = isAndroid ? 'ws://10.0.2.2:8000/ws' : 'ws://127.0.0.1:8000/ws';
      soundBaseUrl = localSoundUrl;
      print("✅ Using LOCAL backend: $baseUrl");
      print("🔊 Using LOCAL sound API: $soundBaseUrl");
    } catch (_) {
      // Fallback to production URL
      baseUrl = 'https://arnavam-afs-backend.hf.space';
      wsUrl = 'wss://arnavam-afs-backend.hf.space/ws';
      // In production, sound API might be on a different path or subdomain
      // For now, we'll just keep it as is or point to a default
      soundBaseUrl = 'https://arnavam-afs-sound.hf.space'; 
      print("🌍 Using PRODUCTION backend: $baseUrl");
    }
  }
}
