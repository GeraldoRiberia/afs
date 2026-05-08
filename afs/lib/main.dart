import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;


import 'package:camera/camera.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';

import 'theme.dart';
import 'screens/settings_screen.dart';
import 'widgets/hud_stat_tile.dart';
import 'widgets/afs_controls_bar.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/config.dart';

// Top level function for Isolate
Future<Uint8List?> _processImageInIsolate(Map<String, dynamic> params) async {
  try {
    final bytes = params['bytes'] as Uint8List;
    img.Image? decodedImage = img.decodeImage(bytes);
    if (decodedImage != null) {
      List<int> jpgBytes = img.encodeJpg(decodedImage, quality: 85);
      return Uint8List.fromList(jpgBytes);
    }
    return bytes;
  } catch (e) {
    print("Isolate error: $e");
    return null;
  }
}

// Global cache for mobile cameras
late List<CameraDescription> _mobileCameras;

enum TrackingMode {
  single, // Maps to face_model.py
  multi,  // Maps to objtrack.py
}

bool get _isMacOSPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
bool get _isAndroidPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackendConfig.init();
  if (!_isMacOSPlatform) {
    try {
      _mobileCameras = await availableCameras();
    } on CameraException catch (e) {
      debugPrint('Error: ${e.code}\nError Message: ${e.description}');
      _mobileCameras = [];
    }
  }
  
  final isLoggedIn = await AuthService.instance.isLoggedIn();
  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AFS — Auto Framing Software',
      debugShowCheckedModeBanner: false,
      theme: AfsTheme.themeData,
      home: isLoggedIn ? const CameraScreen() : const OnboardingScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final FlutterTts _flutterTts = FlutterTts();

  // Mobile Controller
  CameraController? _mobileController;

  // MacOS Controller
  CameraMacOSController? _macOSController;

  bool _isCameraInitialized = false;
  TrackingMode _currentMode = TrackingMode.single;

  // Backend state
  WebSocketChannel? _channel;
  bool _isConnected = false;


  // Zoom state
  Map<String, dynamic>? _latestTrackingResult;
  Timer? _frameTimer;
  bool _isProcessingFrame = false;
  bool _isWaitingForServer = false;
  DateTime? _lastSentTime;

  // Sound Direction state
  double? _soundAngle;
  String? _soundLabel;
  Timer? _soundTimer;

  // FPS tracking
  int _framesSent = 0;
  DateTime? _fpsWindowStart;
  double _currentFps = 0.0;

  // Auto-framing Target state
  Offset _targetNormalizedCenter = const Offset(0.5, 0.5);
  double _targetScale = 1.0;
  bool _showBoundingBoxes = false;
  double _userZoomSliderValue = 0.0;

  double get _zoomMultiplier => math.pow(3.0, _userZoomSliderValue).toDouble();

  // Device List
  List<dynamic> _availableDevices = [];
  dynamic _selectedDevice;

  // Audio Device List (macOS only)
  List<dynamic> _availableAudioDevices = [];
  dynamic _selectedAudioDevice;

  // Backend address
  final String _backendUrl = BackendConfig.wsUrl;

  // ── Recording state ───────────────────────────────────────────────────────
  bool _isRecording = false;
  DateTime? _recordingStart;
  Timer? _recordingTimer;
  Duration _recordingElapsed = Duration.zero;

  // ── Connection toggle ──────────────────────────────────────────────────────
  bool _autoReconnect = true;

  // ── HUD visibility ─────────────────────────────────────────────────────────
  bool _hudVisible = true;

  // ── Enrollment State ───────────────────────────────────────────────────────
  bool _isEnrolling = false;
  String _enrollmentInstruction = '';
  bool _isEnrollmentProcessing = false;

  // ── Syphon Virtual Camera ──────────────────────────────────────────────────
  bool _isSyphonActive = false;


  @override
  void initState() {
    super.initState();
    _initTts();
    _connectWebSocket();
    _initializeCameraList();
    _startSoundPolling();
  }

  void _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  void _connectWebSocket() async {
    if (!_autoReconnect) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_backendUrl));
      _isConnected = true;
      _sendModeUpdate();

      final token = await AuthService.instance.getToken();
      if (token != null && token.isNotEmpty) {
        _channel!.sink.add(jsonEncode({"type": "auth", "token": token}));
      }

      _channel!.stream.listen((message) {
        try {
          final data = jsonDecode(message);
          if (mounted) {
            setState(() {
              // Handle Syphon acknowledgements
              if (data['type'] == 'syphon_ack') {
                _isSyphonActive = data['status'] == 'started';
                return;
              }
              _isWaitingForServer = false;
              _latestTrackingResult = data;
              _updateAutoFraming(data);
            });
          }
        } catch (_) {
          _scheduleReconnection();
        }
      }, onDone: () {
        debugPrint("WebSocket disconnected");
        if (mounted) setState(() { _isConnected = false; _isWaitingForServer = false; });
        if (_autoReconnect) {
          Future.delayed(const Duration(seconds: 3), _connectWebSocket);
        }
      }, onError: (error) {
        debugPrint("WebSocket Error: $error");
        if (mounted) setState(() { _isConnected = false; _isWaitingForServer = false; });
      });
    } catch (_) {
      debugPrint("Could not connect to WebSocket");
    }
  }

  void _disconnectWebSocket() {
    _autoReconnect = false;
    _channel?.sink.close();
    _channel = null;
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isWaitingForServer = false;
        _latestTrackingResult = null;
        _targetScale = 1.0;
        _targetNormalizedCenter = const Offset(0.5, 0.5);
      });
    }
  }

  void _toggleConnection() {
    if (_isConnected) {
      _disconnectWebSocket();
    } else {
      setState(() => _autoReconnect = true);
      _connectWebSocket();
    }
  }

  void _resetZoom() {
    setState(() {
      _targetScale = 1.0;
      _targetNormalizedCenter = const Offset(0.5, 0.5);
      _latestTrackingResult = null;
    });
    // Tell the backend to drop its current target and re-detect
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode({'reset': true}));
    }
  }

  void _scheduleReconnection() {
    if (_autoReconnect) {
      Future.delayed(const Duration(seconds: 3), _connectWebSocket);
    }
  }

  void _sendModeUpdate() {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode({"mode": _currentMode.name}));
    }
  }

  void _sendZoomScale() {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode({"zoom_scale": _zoomMultiplier}));
    }
  }

  // ── Syphon Virtual Camera Toggle ───────────────────────────────────────────
  void _toggleSyphon() {
    if (!_isConnected || _channel == null) return;
    if (_isSyphonActive) {
      _channel!.sink.add(jsonEncode({'command': 'stop_syphon'}));
    } else {
      // camera_idx: 0 = default system camera (same as cv2.VideoCapture(0)).
      // macOS typically assigns the built-in camera as 0, external USB as 1+.
      _channel!.sink.add(jsonEncode({'command': 'start_syphon', 'camera_idx': 0}));
    }
    // Optimistically update state; the syphon_ack will confirm/correct it.
    setState(() => _isSyphonActive = !_isSyphonActive);
  }

  void _updateAutoFraming(Map<String, dynamic> data) {
    if (_isEnrolling) {
      _targetScale = 1.0;
      _targetNormalizedCenter = const Offset(0.5, 0.5);
      return;
    }

    if (data['frame_width'] != null && data['frame_height'] != null) {
      double fw = data['frame_width'].toDouble();
      double fh = data['frame_height'].toDouble();

      Rect? targetRect;
      if (_currentMode == TrackingMode.single && data['boxes'] != null) {
        final boxes = data['boxes'] as List;
        for (var b in boxes) {
          if (b['is_target'] == true || boxes.length == 1) {
            targetRect = Rect.fromLTRB(b['x1'].toDouble(), b['y1'].toDouble(),
                b['x2'].toDouble(), b['y2'].toDouble());
            break;
          }
        }
      } else if (_currentMode == TrackingMode.multi &&
          data['aggregate_box'] != null) {
        var ab = data['aggregate_box'];
        targetRect = Rect.fromLTRB(ab['x1'].toDouble(), ab['y1'].toDouble(),
            ab['x2'].toDouble(), ab['y2'].toDouble());
      }

      if (targetRect != null && fw > 0 && fh > 0) {
        double ncx = targetRect.center.dx / fw;
        double ncy = targetRect.center.dy / fh;
        double nW = targetRect.width / fw;
        double nH = targetRect.height / fh;

        double maxDim = (nW > nH ? nW : nH);
        double paddingFactor = 2.0;
        double targetS = 1.0 / (maxDim * paddingFactor);
        
        targetS = targetS * _zoomMultiplier;
        targetS = targetS.clamp(1.0, 10.0);

        if ((targetS - _targetScale).abs() > 0.05) _targetScale = targetS;
        if ((ncx - _targetNormalizedCenter.dx).abs() > 0.03 ||
            (ncy - _targetNormalizedCenter.dy).abs() > 0.03) {
          _targetNormalizedCenter = Offset(ncx, ncy);
        }
      } else {
        _targetNormalizedCenter = const Offset(0.5, 0.5);
        _targetScale = 1.0;
      }
    }
  }

  void _startFrameLoop() {
    _frameTimer?.cancel();
    _frameTimer =
        Timer.periodic(const Duration(milliseconds: 50), (timer) async {
      if (_lastSentTime != null &&
          DateTime.now().difference(_lastSentTime!).inSeconds > 2) {
        _isWaitingForServer = false;
      }
      if (!_isConnected ||
          _isProcessingFrame ||
          !_isCameraInitialized ||
          _isWaitingForServer) return;

      _isProcessingFrame = true;
      try {
        Uint8List? frameBytes;

        if (_isMacOSPlatform && _macOSController != null) {
          final pic = await _macOSController!.takePicture();
          if (pic != null && pic.bytes != null) {
            frameBytes = await compute(_processImageInIsolate, {
              'bytes': pic.bytes!,
              'isMacOS': true,
            });
          }
        } else if (_mobileController != null &&
            _mobileController!.value.isInitialized) {
          final xFile = await _mobileController!.takePicture();
          final bytes = await xFile.readAsBytes();
          frameBytes = await compute(_processImageInIsolate, {
            'bytes': bytes,
            'isMacOS': false,
          });
        }

        if (frameBytes != null && _channel != null) {
          _isWaitingForServer = true;
          _lastSentTime = DateTime.now();
          _channel!.sink.add(frameBytes);

          // FPS tracking
          _framesSent++;
          _fpsWindowStart ??= DateTime.now();
          final elapsed =
              DateTime.now().difference(_fpsWindowStart!).inMilliseconds;
          if (elapsed >= 2000) {
            if (mounted) {
              setState(() {
                _currentFps = (_framesSent / (elapsed / 1000.0));
                _framesSent = 0;
                _fpsWindowStart = DateTime.now();
              });
            }
          }
        }
      } catch (_) {
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  Future<void> _initializeCameraList() async {
    if (!_isMacOSPlatform) {
      var status = await Permission.camera.request();
      if (!status.isGranted) return;
    }

    if (_isMacOSPlatform) {
      try {
        final videoDevices = await CameraMacOS.instance
            .listDevices(deviceType: CameraMacOSDeviceType.video);
        final audioDevices = await CameraMacOS.instance
            .listDevices(deviceType: CameraMacOSDeviceType.audio);
        setState(() {
          _availableDevices = videoDevices;
          _availableAudioDevices = audioDevices;
          if (audioDevices.isNotEmpty) _selectedAudioDevice = audioDevices.first;
          if (videoDevices.isNotEmpty) {
            _selectedDevice = videoDevices.first;
            _initializeMacOSCamera(_selectedDevice);
          }
        });
      } catch (_) {}
    } else {
      setState(() {
        _availableDevices = _mobileCameras;
        if (_mobileCameras.isNotEmpty) {
          _selectedDevice = _mobileCameras.first;
          _initializeMobileCamera(_selectedDevice);
        }
      });
    }
  }

  Future<void> _initializeMacOSCamera(CameraMacOSDevice device) async {
    setState(() => _isCameraInitialized = true);
    Future.delayed(const Duration(milliseconds: 1000), _startFrameLoop);
  }

  Future<void> _initializeMobileCamera(CameraDescription camera) async {
    if (_mobileController != null) await _mobileController!.dispose();
    _mobileController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
    );
    try {
      await _mobileController!.initialize();
      if (mounted) {
        setState(() => _isCameraInitialized = true);
        _startFrameLoop();
      }
    } on CameraException catch (_) {
    }
  }

  void _onDeviceSelected(dynamic device) {
    if (device == _selectedDevice) return;
    setState(() {
      _selectedDevice = device;
      _isCameraInitialized = false;
    });
    if (_isMacOSPlatform) {
      _initializeMacOSCamera(device as CameraMacOSDevice);
    } else {
      _initializeMobileCamera(device as CameraDescription);
    }
  }

  void _onAudioDeviceSelected(dynamic device) {
    setState(() => _selectedAudioDevice = device);
  }

  // ── Recording ─────────────────────────────────────────────────────────────
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!_isCameraInitialized) return;
    try {
      if (_isMacOSPlatform && _macOSController != null) {
        final dir = await getApplicationDocumentsDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final path = '${dir.path}/AFS_REC_$ts.mov';
        await _macOSController!.recordVideo(
          url: path,
          enableAudio: true,
        );
      } else if (_mobileController != null &&
          _mobileController!.value.isInitialized) {
        await _mobileController!.startVideoRecording();
      }
      if (mounted) {
        setState(() {
          _isRecording = true;
          _recordingStart = DateTime.now();
          _recordingElapsed = Duration.zero;
        });
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted && _recordingStart != null) {
            setState(() {
              _recordingElapsed =
                  DateTime.now().difference(_recordingStart!);
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Start recording error: $e');
    }
  }

  Future<String?> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    String? savedPath;
    try {
      if (_isMacOSPlatform && _macOSController != null) {
        final file = await _macOSController!.stopRecording();
        if (file != null) {
          final dir = await getApplicationDocumentsDirectory();
          final ts = DateTime.now().millisecondsSinceEpoch;
          savedPath = '${dir.path}/AFS_REC_$ts.mov';
          if (file.bytes != null) {
            await File(savedPath).writeAsBytes(file.bytes!);
          } else {
            savedPath = null;
          }
        }
      } else if (_mobileController != null) {
        final xfile = await _mobileController!.stopVideoRecording();
        savedPath = xfile.path;
      }
    } catch (e) {
      debugPrint('Stop recording error: $e');
    }
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingStart = null;
        _recordingElapsed = Duration.zero;
      });
      if (savedPath != null && !_isEnrolling) {
        _showSavedSnackbar(savedPath);
      }
    }
    return savedPath;
  }

  Future<void> _startEnrollmentSequence() async {
    if (!await AuthService.instance.isLoggedIn()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in to enroll your face.')));
      return;
    }

    setState(() {
      _isEnrolling = true;
      _enrollmentInstruction = 'Get ready...';
      _isEnrollmentProcessing = false;
    });

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted || !_isEnrolling) return;
    
    await _startRecording();
    
    // Step 1: Look Straight
    setState(() => _enrollmentInstruction = 'Look straight at the camera');
    await _speak('Look straight at the camera');
    bool stepDone = false;
    DateTime startTime = DateTime.now();
    while (mounted && _isEnrolling && !stepDone) {
      if (_latestTrackingResult != null) {
        final boxes = _latestTrackingResult!['boxes'] as List?;
        if (boxes != null && boxes.isNotEmpty) {
          final yaw = boxes.first['yaw'] as num? ?? 0.0;
          final pitch = boxes.first['pitch'] as num? ?? 0.0;
          if (yaw.abs() < 0.15 && pitch.abs() < 0.15) {
             stepDone = true;
          }
        }
      }
      if (DateTime.now().difference(startTime).inSeconds > 5) stepDone = true; // timeout
      await Future.delayed(const Duration(milliseconds: 200));
    }
    
    await _speak('Good');
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted || !_isEnrolling) return;

    // Step 2: Turn Head
    setState(() => _enrollmentInstruction = 'Slowly turn your head to one side');
    await _speak('Slowly turn your head to one side');
    stepDone = false;
    startTime = DateTime.now();
    double firstTurnYaw = 0.0;
    while (mounted && _isEnrolling && !stepDone) {
      if (_latestTrackingResult != null) {
        final boxes = _latestTrackingResult!['boxes'] as List?;
        if (boxes != null && boxes.isNotEmpty) {
          final yaw = boxes.first['yaw'] as num? ?? 0.0;
          if (yaw.abs() > 0.15) {
             firstTurnYaw = yaw.toDouble();
             stepDone = true;
          }
        }
      }
      if (DateTime.now().difference(startTime).inSeconds > 8) stepDone = true;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    await _speak('Great');
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted || !_isEnrolling) return;

    // Step 3: Turn Head Opposite
    setState(() => _enrollmentInstruction = 'Now slowly turn to the other side');
    await _speak('Now slowly turn your head to the other side');
    stepDone = false;
    startTime = DateTime.now();
    while (mounted && _isEnrolling && !stepDone) {
      if (_latestTrackingResult != null) {
        final boxes = _latestTrackingResult!['boxes'] as List?;
        if (boxes != null && boxes.isNotEmpty) {
          final yaw = boxes.first['yaw'] as num? ?? 0.0;
          if (firstTurnYaw > 0 ? yaw < -0.15 : yaw > 0.15) stepDone = true;
        }
      }
      if (DateTime.now().difference(startTime).inSeconds > 8) stepDone = true;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    await _speak('Perfect');
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted || !_isEnrolling) return;

    // Step 4: Look Up or Down
    setState(() => _enrollmentInstruction = 'Look slightly up or down');
    await _speak('Finally, look slightly up or down');
    stepDone = false;
    startTime = DateTime.now();
    while (mounted && _isEnrolling && !stepDone) {
      if (_latestTrackingResult != null) {
        final boxes = _latestTrackingResult!['boxes'] as List?;
        if (boxes != null && boxes.isNotEmpty) {
          final pitch = boxes.first['pitch'] as num? ?? 0.0;
          if (pitch.abs() > 0.10) stepDone = true;
        }
      }
      if (DateTime.now().difference(startTime).inSeconds > 6) stepDone = true;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    
    await _speak('Done');
    await Future.delayed(const Duration(milliseconds: 2000));

    setState(() {
      _enrollmentInstruction = 'Processing...';
      _isEnrollmentProcessing = true;
    });

    String? savedPath = await _stopRecording();

    if (savedPath != null) {
      try {
        await AuthService.instance.enrollFace(savedPath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Face Enrolled Successfully!')));
          _disconnectWebSocket();
          _autoReconnect = true;
          _connectWebSocket();
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enrollment Failed: $e')));
      }
    }

    if (mounted) setState(() { _isEnrolling = false; _isEnrollmentProcessing = false; });
  }

  void _showSavedSnackbar(String path) {
    final filename = path.split('/').last;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AfsTheme.surfaceHighest,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: AfsTheme.neonGreen, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recording saved',
                      style: AfsTheme.bodySmall(AfsTheme.ashGray)),
                  Text(filename,
                      style: AfsTheme.monoSmall(
                          AfsTheme.ashGray.withValues(alpha: 0.6)),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _recordingTimer?.cancel();
    _soundTimer?.cancel();
    _channel?.sink.close();
    _mobileController?.dispose();
    super.dispose();
  }

  // ── Sound Polling ──────────────────────────────────────────────────────────
  void _startSoundPolling() {
    _soundTimer?.cancel();
    _soundTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!mounted) return;
      try {
        final response = await http
            .get(Uri.parse('${BackendConfig.soundBaseUrl}/latest'))
            .timeout(const Duration(milliseconds: 400));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (mounted) {
            setState(() {
              _soundAngle = data['angle_deg'];
              _soundLabel = data['label'];
            });
          }
        }
      } catch (_) {
        // Silent fail for polling
      }
    });
  }

  String get _soundDirectionIndicator {
    if (_soundAngle == null || _soundLabel == null) return '—';
    if (_soundLabel != 'Speech') return '—'; // Only show for speech
    
    final angleStr = '${_soundAngle!.toStringAsFixed(1)}°';
    // Threshold to avoid jitter
    if (_soundAngle! < -10) return '← $angleStr';
    if (_soundAngle! > 10) return '→ $angleStr';
    return '↑ $angleStr'; // Centered
  }

  // ── Camera Widget ──────────────────────────────────────────────────────────
  Widget _buildCameraWidget() {
    if (!_isCameraInitialized && !_isMacOSPlatform) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_isMacOSPlatform) {
      return _selectedDevice != null
          ? CameraMacOSView(
              // Rebuild when video OR audio device changes
              key: ValueKey(
                '${(_selectedDevice as CameraMacOSDevice).deviceId}'
                '_${(_selectedAudioDevice as CameraMacOSDevice?)?.deviceId ?? 'default'}',
              ),
              fit: BoxFit.cover,
              deviceId: (_selectedDevice as CameraMacOSDevice).deviceId,
              audioDeviceId:
                  (_selectedAudioDevice as CameraMacOSDevice?)?.deviceId,
              cameraMode: CameraMacOSMode.photo,
              enableAudio: true,
              onCameraInizialized: (CameraMacOSController controller) {
                _macOSController = controller;
                if (!_isCameraInitialized) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    setState(() => _isCameraInitialized = true);
                  });
                }
              },
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_off_rounded,
                      size: 48, color: AfsTheme.ashGray.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text('No Camera Selected',
                      style: AfsTheme.bodyMedium(
                          AfsTheme.ashGray.withValues(alpha: 0.5))),
                ],
              ),
            );
    }
    if (_mobileController != null && _mobileController!.value.isInitialized) {
      return CameraPreview(_mobileController!);
    }
    return const Center(child: CircularProgressIndicator());
  }

  // ── Tracking Stats ─────────────────────────────────────────────────────────
  int get _detectedCount {
    if (_latestTrackingResult == null) return 0;
    if (_currentMode == TrackingMode.single) {
      return (_latestTrackingResult!['boxes'] as List?)?.length ?? 0;
    }
    return (_latestTrackingResult!['individual_boxes'] as List?)?.length ?? 0;
  }

  String get _zoomLabel =>
      '${_zoomMultiplier.toStringAsFixed(2)}×';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final W = constraints.maxWidth;
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        // Sidebar reserves space only when wide AND the user hasn't hidden it
        final isWide = isLandscape && W > 800;
        final reserveSpace = isWide && _hudVisible;
        // Show HUD whenever user wants it (overlay when narrow, inline when wide)
        final showHud = _hudVisible;

        double S = _targetScale;
        double ncx = _targetNormalizedCenter.dx;
        double ncy = _targetNormalizedCenter.dy;
        Offset targetCenter = _targetNormalizedCenter;

        const double controlBarH = 72.0;
        // Removed unused topBarH
        const double sidebarW = 220.0;

        final cameraWidget = _buildCameraWidget();

        return Scaffold(
          backgroundColor: AfsTheme.surfaceDim,
          body: Column(
            children: [
              // Top status bar
              _TopStatusBar(
                isConnected: _isConnected,
                mode: _currentMode,
                fps: _currentFps,
                isRecording: _isRecording,
                recordingElapsed: _recordingElapsed,
                hudVisible: _hudVisible,
                onHudToggle: () => setState(() => _hudVisible = !_hudVisible),
                onSettings: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      availableDevices: _availableDevices,
                      selectedDevice: _selectedDevice,
                      onDeviceSelected: _onDeviceSelected,
                      availableAudioDevices: _availableAudioDevices,
                      selectedAudioDevice: _selectedAudioDevice,
                      onAudioDeviceSelected: _onAudioDeviceSelected,
                    ),
                  ),
                ),
                onLogout: () async {
                  await AuthService.instance.logout();
                  if (!context.mounted) return;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
              ),
              Expanded(
                child: Row(
                  children: [

                    Expanded(
                      child: Stack(
            fit: StackFit.expand,
            children: [
              // ── 1. Camera with animation ──────────────────
              Positioned(
                top: 0,
                left: 0,
                right: reserveSpace ? sidebarW : 0,
                bottom: controlBarH,
                child: ClipRect(
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 1500),
                    curve: Curves.fastOutSlowIn,
                    tween: Tween<double>(begin: 1.0, end: S),
                    builder: (context, scale, child) {
                      return TweenAnimationBuilder<Alignment>(
                        duration: const Duration(milliseconds: 1500),
                        curve: Curves.fastOutSlowIn,
                        // We use Alignment simply as a convenient 2D vector for ncx/ncy interpolation
                        tween: AlignmentTween(
                            begin: const Alignment(0.5, 0.5), 
                            end: Alignment(targetCenter.dx, targetCenter.dy)),
                        builder: (context, centerVec, innerChild) {
                          double cw = 1.0 / scale;
                          double ch = 1.0 / scale;
                          
                          // Clamp the target center so we don't pan out of bounds and reveal black borders
                          double cx = centerVec.x.clamp(cw / 2, 1.0 - cw / 2);
                          double cy = centerVec.y.clamp(ch / 2, 1.0 - ch / 2);
                          
                          double aX = 0.0;
                          double aY = 0.0;
                          if (scale > 1.001) {
                            // Compute the precise Transform Alignment needed to map (cx, cy) to the center of the screen
                            aX = (scale / (scale - 1.0)) * (cx * 2.0 - 1.0);
                            aY = (scale / (scale - 1.0)) * (cy * 2.0 - 1.0);
                          }
                          
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Transform(
                                alignment: Alignment(aX, aY),
                                transform: Matrix4.identity()..scale(scale, scale),
                                child: innerChild,
                              ),
                              if (_showBoundingBoxes)
                                CustomPaint(
                                  painter: BoundingBoxPainter(
                                    data: _latestTrackingResult,
                                    mode: _currentMode,
                                    scaleOffset: scale,
                                    alignOffset: Alignment(aX, aY),
                                  ),
                                ),
                            ],
                          );
                        },
                        child: child,
                      );
                    },
                    child: cameraWidget,
                  ),
                ),
              ),

              // Removed duplicated Top Status bar since we moved it above the Row

              // ── 3. Face Enrollment Overlay ─────────────────────────────────
              if (_isEnrolling)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.8),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 280,
                            height: 380,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _isEnrollmentProcessing ? AfsTheme.mintGreen : AfsTheme.neonGreen, 
                                width: 4
                              ),
                              borderRadius: BorderRadius.circular(200),
                            ),
                          ),
                          const SizedBox(height: 40),
                          Text(
                            _enrollmentInstruction,
                            style: AfsTheme.displaySmall(AfsTheme.neonGreen).copyWith(fontSize: 24),
                            textAlign: TextAlign.center,
                          ),
                          if (_isEnrollmentProcessing)
                            const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: CircularProgressIndicator(color: AfsTheme.neonGreen),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── 4. Right HUD Sidebar ───────────────────────────────────
              // On wide screens: reserved inline space.
              // On narrow screens: floating overlay with semi-transparent backdrop.
              if (showHud)
                Positioned(
                  top: 0,
                  right: 0,
                  width: sidebarW,
                  bottom: controlBarH,
                  child: Stack(
                    children: [
                      // Dim backdrop only when overlaying (narrow mode)
                      if (!reserveSpace)
                        GestureDetector(
                          onTap: () => setState(() => _hudVisible = false),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.0),
                          ),
                        ),
                      _HudSidebar(
                        isConnected: _isConnected,
                        detectedCount: _detectedCount,
                        zoom: _zoomLabel,
                        fps: _currentFps,
                        mode: _currentMode,
                        hasTarget: _targetScale > 1.05,
                        userZoomSliderValue: _userZoomSliderValue,
                        soundDirection: _soundDirectionIndicator,
                        soundLabel: _soundLabel,
                        onConnectionToggle: _toggleConnection,
                        onZoomReset: () {
                          setState(() => _userZoomSliderValue = 0.0);
                          _sendZoomScale();
                          _resetZoom();
                        },
                        onEnrollFace: _startEnrollmentSequence,
                        onZoomScaleChanged: (val) {
                          setState(() => _userZoomSliderValue = val);
                          _sendZoomScale();
                        },
                      ),
                    ],
                  ),
                ),

              // ── 5. Bottom Controls Bar ─────────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: controlBarH,
                child: AfsControlsBar(
                  modeSelector: TrackingModeSelector(
                    modes: const [
                      ChipModeItem(label: 'Single', icon: Icons.person_rounded),
                      ChipModeItem(
                          label: 'Multi', icon: Icons.groups_2_rounded),
                    ],
                    activeIndex: _currentMode.index,
                    onSelect: (i) {
                      setState(() {
                        _currentMode = TrackingMode.values[i];
                        _latestTrackingResult = null;
                      });
                      _sendModeUpdate();
                    },
                  ),
                  showBoundingBoxes: _showBoundingBoxes,
                  onBoundingBoxToggle: (v) =>
                      setState(() => _showBoundingBoxes = v),
                  isRecording: _isRecording,
                  onRecordToggle: _toggleRecording,
                  isSyphonActive: _isSyphonActive,
                  onSyphonToggle: (_) => _toggleSyphon(),
                ),
              ),
            ],
          ), // End Stack
        ), // End Expanded
      ],
    ), // End Row
  ), // End Expanded
],
          ), // End Column
        ); // End Scaffold
      }, // End LayoutBuilder builder
    ); // End LayoutBuilder
  } // End build method

}

// ── Top Status Bar ────────────────────────────────────────────────────────────
class _TopStatusBar extends StatefulWidget {
  final bool isConnected;
  final TrackingMode mode;
  final double fps;
  final bool isRecording;
  final Duration recordingElapsed;
  final bool hudVisible;
  final VoidCallback? onHudToggle;
  final VoidCallback? onSettings;
  final VoidCallback? onLogout;

  const _TopStatusBar({
    required this.isConnected,
    required this.mode,
    required this.fps,
    required this.isRecording,
    required this.recordingElapsed,
    required this.hudVisible,
    this.onHudToggle,
    this.onSettings,
    this.onLogout,
  });

  @override
  State<_TopStatusBar> createState() => _TopStatusBarState();
}

class _TopStatusBarState extends State<_TopStatusBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _recPulse;
  late Animation<double> _recAlpha;

  @override
  void initState() {
    super.initState();
    _recPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _recAlpha = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _recPulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _recPulse.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AfsTheme.surfaceLow.withValues(alpha: 0.88),
            border: Border(
              bottom: BorderSide(color: AfsTheme.outlineGhost, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Connection dot
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: widget.isConnected ? AfsTheme.neonGreen : AfsTheme.errorColor,
                  shape: BoxShape.circle,
                  boxShadow: widget.isConnected
                      ? [
                          BoxShadow(
                            color: AfsTheme.neonGreen.withValues(alpha: 0.8),
                            blurRadius: 6,
                          )
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Text('AFS', style: AfsTheme.monoMedium(AfsTheme.neonGreen)),
              const SizedBox(width: 6),
              Text('Auto Framing Software',
                  style: AfsTheme.bodySmall(
                      AfsTheme.ashGray.withValues(alpha: 0.5))),

              const Spacer(),

              // ── REC indicator (only when recording) ──
              if (widget.isRecording)
                AnimatedBuilder(
                  animation: _recAlpha,
                  builder: (context, _) {
                    return Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AfsTheme.errorColor
                            .withValues(alpha: _recAlpha.value * 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AfsTheme.errorColor
                              .withValues(alpha: _recAlpha.value * 0.7),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: AfsTheme.errorColor
                                  .withValues(alpha: _recAlpha.value),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'REC  ${_formatDuration(widget.recordingElapsed)}',
                            style: AfsTheme.labelSmall(AfsTheme.errorColor),
                          ),
                        ],
                      ),
                    );
                  },
                ),

              // FPS badge
              if (widget.fps > 0) ...[
                _StatusBadge(
                  label: '${widget.fps.toStringAsFixed(1)} fps',
                  color: AfsTheme.infoColor,
                ),
                const SizedBox(width: 8),
              ],

              // Connection status
              _StatusBadge(
                label: widget.isConnected ? 'CONNECTED' : 'DISCONNECTED',
                color: widget.isConnected ? AfsTheme.neonGreen : AfsTheme.errorColor,
              ),

              const SizedBox(width: 8),

              // HUD toggle button
              if (widget.onHudToggle != null) ...[
                GestureDetector(
                  onTap: widget.onHudToggle,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: widget.hudVisible
                          ? AfsTheme.neonGreen.withValues(alpha: 0.12)
                          : AfsTheme.surfaceHighest,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.hudVisible
                            ? AfsTheme.neonGreen.withValues(alpha: 0.35)
                            : Colors.transparent,
                      ),
                    ),
                    child: Icon(
                      widget.hudVisible
                          ? Icons.view_sidebar_rounded
                          : Icons.view_sidebar_outlined,
                      size: 15,
                      color: widget.hudVisible
                          ? AfsTheme.neonGreen
                          : AfsTheme.ashGray,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],

              // Settings button
              if (widget.onSettings != null)
                GestureDetector(
                  onTap: widget.onSettings,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AfsTheme.surfaceHighest,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.settings_rounded,
                        size: 15, color: AfsTheme.ashGray),
                  ),
                ),

              const SizedBox(width: 6),

              // Logout button
              if (widget.onLogout != null)
                GestureDetector(
                  onTap: widget.onLogout,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AfsTheme.surfaceHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.logout_rounded,
                        size: 15,
                        color: AfsTheme.ashGray.withValues(alpha: 0.7)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: AfsTheme.labelSmall(color)),
    );
  }
}

// ── HUD Sidebar ───────────────────────────────────────────────────────────────
class _HudSidebar extends StatelessWidget {
  final bool isConnected;
  final int detectedCount;
  final String zoom;
  final double fps;
  final TrackingMode mode;
  final bool hasTarget;
  final double userZoomSliderValue;
  final String soundDirection;
  final String? soundLabel;
  final VoidCallback onConnectionToggle;
  final VoidCallback onZoomReset;
  final VoidCallback onEnrollFace;
  final ValueChanged<double> onZoomScaleChanged;

  const _HudSidebar({
    required this.isConnected,
    required this.detectedCount,
    required this.zoom,
    required this.fps,
    required this.mode,
    required this.hasTarget,
    required this.userZoomSliderValue,
    required this.soundDirection,
    this.soundLabel,
    required this.onConnectionToggle,
    required this.onZoomReset,
    required this.onEnrollFace,
    required this.onZoomScaleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: AfsTheme.surfaceContainer.withValues(alpha: 0.88),
            border: Border(
              left: BorderSide(color: AfsTheme.outlineGhost, width: 1),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TRACKING HUD',
                  style: AfsTheme.labelSmall(
                      AfsTheme.ashGray.withValues(alpha: 0.4))),
              const SizedBox(height: 16),

              HudStatTile(
                label: 'MODE',
                value: mode == TrackingMode.single ? 'SINGLE' : 'MULTI',
                icon: mode == TrackingMode.single
                    ? Icons.person_rounded
                    : Icons.groups_2_rounded,
              ),
              const SizedBox(height: 10),

              HudStatTile(
                label: 'DETECTED',
                value: '$detectedCount',
                icon: Icons.track_changes_rounded,
                valueColor: detectedCount > 0
                    ? AfsTheme.neonGreen
                    : AfsTheme.ashGray.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 10),

              HudStatTile(
                label: 'AUTO ZOOM',
                value: zoom,
                icon: Icons.zoom_in_rounded,
                onTap: onZoomReset,
              ),
              const SizedBox(height: 4),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: AfsTheme.neonGreen,
                  inactiveTrackColor: AfsTheme.neonGreen.withValues(alpha: 0.2),
                  thumbColor: AfsTheme.neonGreen,
                  overlayColor: AfsTheme.neonGreen.withValues(alpha: 0.1),
                  trackHeight: 2.0,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                ),
                child: Slider(
                  value: userZoomSliderValue,
                  min: -1.0,
                  max: 1.0,
                  onChanged: onZoomScaleChanged,
                ),
              ),
              const SizedBox(height: 10),

              HudStatTile(
                label: 'SEND RATE',
                value: fps > 0 ? '${fps.toStringAsFixed(1)} fps' : '—',
                icon: Icons.speed_rounded,
              ),
              const SizedBox(height: 10),

              HudStatTile(
                label: 'SOUND DIR',
                value: soundDirection,
                icon: Icons.mic_rounded,
                valueColor: soundDirection != '—' ? AfsTheme.neonGreen : AfsTheme.ashGray.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onEnrollFace,
                  icon: const Icon(Icons.face_retouching_natural, size: 16),
                  label: const Text('Enroll Face'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AfsTheme.surfaceHigh,
                    foregroundColor: AfsTheme.neonGreen,
                    side: const BorderSide(color: AfsTheme.neonGreen, width: 1),
                  ),
                ),
              ),

              const Spacer(),

              // ── Backend connection toggle strip ──
              GestureDetector(
                onTap: onConnectionToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? AfsTheme.neonGreen.withValues(alpha: 0.08)
                        : AfsTheme.errorColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isConnected
                          ? AfsTheme.neonGreen.withValues(alpha: 0.25)
                          : AfsTheme.errorColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isConnected
                              ? AfsTheme.neonGreen
                              : AfsTheme.errorColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (isConnected
                                      ? AfsTheme.neonGreen
                                      : AfsTheme.errorColor)
                                  .withValues(alpha: 0.7),
                              blurRadius: 6,
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          isConnected ? 'Backend Online' : 'Backend Offline',
                          style: AfsTheme.monoSmall(
                            isConnected ? AfsTheme.neonGreen : AfsTheme.errorColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        isConnected
                            ? Icons.power_settings_new_rounded
                            : Icons.power_off_rounded,
                        size: 14,
                        color: isConnected
                            ? AfsTheme.neonGreen.withValues(alpha: 0.6)
                            : AfsTheme.errorColor.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bounding Box Painter ──────────────────────────────────────────────────────


class BoundingBoxPainter extends CustomPainter {
  final Map<String, dynamic>? data;
  final TrackingMode mode;
  final double scaleOffset;
  final Alignment alignOffset;

  BoundingBoxPainter({
    this.data,
    required this.mode,
    required this.scaleOffset,
    required this.alignOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data == null ||
        data!['frame_width'] == null ||
        data!['frame_height'] == null) return;

    double fw = data!['frame_width'].toDouble();
    double fh = data!['frame_height'].toDouble();
    double sw = size.width;
    double sh = size.height;

    double baseScale = [sw / fw, sh / fh].reduce((a, b) => a > b ? a : b);
    double offsetX = (sw - fw * baseScale) / 2;
    double offsetY = (sh - fh * baseScale) / 2;

    double originX = (alignOffset.x + 1.0) / 2.0 * sw;
    double originY = (alignOffset.y + 1.0) / 2.0 * sh;

    Rect mapRect(double x1, double y1, double x2, double y2) {
      double bx1 = x1 * baseScale + offsetX;
      double by1 = y1 * baseScale + offsetY;
      double bx2 = x2 * baseScale + offsetX;
      double by2 = y2 * baseScale + offsetY;
      return Rect.fromLTRB(
        originX + (bx1 - originX) * scaleOffset,
        originY + (by1 - originY) * scaleOffset,
        originX + (bx2 - originX) * scaleOffset,
        originY + (by2 - originY) * scaleOffset,
      );
    }

    final targetPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = AfsTheme.neonGreen;

    final otherPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = AfsTheme.mintGreen.withValues(alpha: 0.7);

    // Corner-bracket drawing helper
    void drawCornerBrackets(Canvas c, Rect r, Paint p, double len) {
      final path = Path()
        // top-left
        ..moveTo(r.left, r.top + len)
        ..lineTo(r.left, r.top)
        ..lineTo(r.left + len, r.top)
        // top-right
        ..moveTo(r.right - len, r.top)
        ..lineTo(r.right, r.top)
        ..lineTo(r.right, r.top + len)
        // bottom-right
        ..moveTo(r.right, r.bottom - len)
        ..lineTo(r.right, r.bottom)
        ..lineTo(r.right - len, r.bottom)
        // bottom-left
        ..moveTo(r.left + len, r.bottom)
        ..lineTo(r.left, r.bottom)
        ..lineTo(r.left, r.bottom - len);
      c.drawPath(path, p);
    }

    if (mode == TrackingMode.single && data!['boxes'] != null) {
      for (var b in data!['boxes']) {
        bool isTarget = b['is_target'] == true;
        final r = mapRect(b['x1'].toDouble(), b['y1'].toDouble(),
            b['x2'].toDouble(), b['y2'].toDouble());
        drawCornerBrackets(canvas, r, isTarget ? targetPaint : otherPaint, 14);
      }
    } else if (mode == TrackingMode.multi) {
      if (data!['individual_boxes'] != null) {
        for (var b in data!['individual_boxes']) {
          final r = mapRect(b['x1'].toDouble(), b['y1'].toDouble(),
              b['x2'].toDouble(), b['y2'].toDouble());
          drawCornerBrackets(canvas, r, otherPaint, 10);
        }
      }
      if (data!['aggregate_box'] != null) {
        var ab = data!['aggregate_box'];
        final r = mapRect(ab['x1'].toDouble(), ab['y1'].toDouble(),
            ab['x2'].toDouble(), ab['y2'].toDouble());
        drawCornerBrackets(canvas, r, targetPaint, 16);
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) => true;
}
