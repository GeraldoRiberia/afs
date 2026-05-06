import 'package:flutter/foundation.dart';

class BackendConfig {
  static String baseUrl = 'http://127.0.0.1:8000';
  static String wsUrl = 'ws://127.0.0.1:8000/ws';
  static String soundBaseUrl = 'http://127.0.0.1:8001';

  static Future<void> init() async {
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final localBaseUrl = isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';
    final localSoundUrl = isAndroid ? 'http://10.0.2.2:8001' : 'http://127.0.0.1:8001';
    
    baseUrl = localBaseUrl;
    wsUrl = isAndroid ? 'ws://10.0.2.2:8000/ws' : 'ws://127.0.0.1:8000/ws';
    print("✅ Using LOCAL backend: $baseUrl");

    soundBaseUrl = localSoundUrl;
    print("🔊 Using LOCAL sound API: $soundBaseUrl");
  }
}
