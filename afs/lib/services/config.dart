import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BackendConfig {
  static String baseUrl = 'https://AutoFramingSoftware-afs-backend.hf.space';
  static String wsUrl = 'wss://AutoFramingSoftware-afs-backend.hf.space/ws';
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
      print("✅ Using LOCAL backend: $baseUrl");
    } catch (_) {
      // Fallback to production URL
      baseUrl = 'https://AutoFramingSoftware-afs-backend.hf.space';
      wsUrl = 'wss://AutoFramingSoftware-afs-backend.hf.space/ws';
      print("🌍 Using PRODUCTION backend: $baseUrl");
    }

    try {
      // Try to connect to localhost:8001
      final response = await http.get(Uri.parse('$localSoundUrl/latest')).timeout(const Duration(milliseconds: 1500));
      soundBaseUrl = localSoundUrl;
      print("🔊 Using LOCAL sound API: $soundBaseUrl");
    } catch (_) {
      soundBaseUrl = 'https://AutoFramingSoftware-afs-sound.hf.space'; 
      print("🌍 Using PRODUCTION sound API: $soundBaseUrl");
    }
  }
}
