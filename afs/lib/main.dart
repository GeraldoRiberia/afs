import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';


import 'package:camera/camera.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:image/image.dart' as img;

import 'theme.dart';
import 'widgets/quick_settings_drawer.dart';
import 'widgets/hud_stat_tile.dart';
import 'widgets/afs_controls_bar.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isMacOS) {
    try {
      _mobileCameras = await availableCameras();
    } on CameraException catch (e) {
      debugPrint('Error: ${e.code}\nError Message: ${e.description}');
      _mobileCameras = [];
    }
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AFS — Auto Framing Software',
      debugShowCheckedModeBanner: false,
      theme: AfsTheme.themeData,
      home: const OnboardingScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  // Mobile Controller
  CameraController? _mobileController;

  // MacOS Controller
  CameraMacOSController? _macOSController;

  bool _isCameraInitialized = false;
  TrackingMode _currentMode = TrackingMode.single;

  // Backend state
  WebSocketChannel? _channel;
  bool _isConnected = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Zoom/Center Stage state
  Map<String, dynamic>? _latestTrackingResult;
  Timer? _frameTimer;
  bool _isProcessingFrame = false;
  bool _isWaitingForServer = false;
  DateTime? _lastSentTime;

  // FPS tracking
  int _framesSent = 0;
  DateTime? _fpsWindowStart;
  double _currentFps = 0.0;

  // Auto-framing Target state
  Offset _targetNormalizedCenter = const Offset(0.5, 0.5);
  double _targetScale = 1.0;
  bool _showBoundingBoxes = false;

  // Device List
  List<dynamic> _availableDevices = [];
  dynamic _selectedDevice;

  // Backend address
  final String _backendUrl =
      Platform.isAndroid ? 'ws://10.0.2.2:8000/ws' : 'ws://127.0.0.1:8000/ws';

  // Sidebar collapse threshold
  static const double _sidebarBreakpoint = 900.0;

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
    _initializeCameraList();
  }

  void _connectWebSocket() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_backendUrl));
      _isConnected = true;
      _sendModeUpdate();

      _channel!.stream.listen((message) {
        try {
          final data = jsonDecode(message);
          if (mounted) {
            setState(() {
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
        Future.delayed(const Duration(seconds: 3), _connectWebSocket);
      }, onError: (error) {
        debugPrint("WebSocket Error: $error");
        if (mounted) setState(() { _isConnected = false; _isWaitingForServer = false; });
      });
    } catch (_) {
      debugPrint("Could not connect to WebSocket");
    }
  }

  void _scheduleReconnection() {
    Future.delayed(const Duration(seconds: 3), _connectWebSocket);
  }

  void _sendModeUpdate() {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode({"mode": _currentMode.name}));
    }
  }

  void _updateAutoFraming(Map<String, dynamic> data) {
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

        double alignX = (ncx * 2.0) - 1.0;
        double alignY = (ncy * 2.0) - 1.0;

        double maxDim = (nW > nH ? nW : nH);
        double paddingFactor = 2.0;
        double targetS = 1.0 / (maxDim * paddingFactor);

        double minSx = 1.0;
        if (alignX.abs() < 0.95) minSx = 1.0 / (1.0 - alignX.abs());
        double minSy = 1.0;
        if (alignY.abs() < 0.95) minSy = 1.0 / (1.0 - alignY.abs());

        if (minSx > targetS) targetS = minSx;
        if (minSy > targetS) targetS = minSy;
        targetS = targetS.clamp(1.0, 3.5);

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
        Timer.periodic(const Duration(milliseconds: 500), (timer) async {
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

        if (Platform.isMacOS && _macOSController != null) {
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
    if (!Platform.isMacOS) {
      var status = await Permission.camera.request();
      if (!status.isGranted) return;
    }

    if (Platform.isMacOS) {
      try {
        List<CameraMacOSDevice> devices = await CameraMacOS.instance
            .listDevices(deviceType: CameraMacOSDeviceType.video);
        setState(() {
          _availableDevices = devices;
          if (devices.isNotEmpty) {
            _selectedDevice = devices.first;
            _initializeMacOSCamera(_selectedDevice);
          }
        });
      } catch (_) {
      }
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
      enableAudio: false,
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
    if (Platform.isMacOS) {
      _initializeMacOSCamera(device as CameraMacOSDevice);
    } else {
      _initializeMobileCamera(device as CameraDescription);
    }
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _channel?.sink.close();
    _mobileController?.dispose();
    super.dispose();
  }

  // ── Camera Widget ──────────────────────────────────────────────────────────
  Widget _buildCameraWidget() {
    if (!_isCameraInitialized && !Platform.isMacOS) {
      return const Center(child: CircularProgressIndicator());
    }
    if (Platform.isMacOS) {
      return _selectedDevice != null
          ? CameraMacOSView(
              key: ValueKey((_selectedDevice as CameraMacOSDevice).deviceId),
              fit: BoxFit.cover,
              deviceId: (_selectedDevice as CameraMacOSDevice).deviceId,
              cameraMode: CameraMacOSMode.photo,
              enableAudio: false,
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
      '${_targetScale.toStringAsFixed(1)}×';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final W = constraints.maxWidth;
        // H was removed because it was unused
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final showSidebar = isLandscape && W > 800;
        
        double S = _targetScale;
        double ncx = _targetNormalizedCenter.dx;
        double ncy = _targetNormalizedCenter.dy;
        double alignX = (ncx * 2.0) - 1.0;
        double alignY = (ncy * 2.0) - 1.0;
        Alignment targetAlignment = Alignment(alignX, alignY);

        const double controlBarH = 72.0;
        // Removed unused topBarH
        const double sidebarW = 220.0;

        final cameraWidget = _buildCameraWidget();

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AfsTheme.surfaceDim,
          endDrawer: const QuickSettingsDrawer(),
          body: Column(
            children: [
              // Default exact top bar match
              _TopStatusBar(
                isConnected: _isConnected,
                mode: _currentMode,
                fps: _currentFps,
                onSettings: () => _scaffoldKey.currentState?.openEndDrawer(),
                onLogout: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    if (showSidebar) _buildLeftSidebar(),
                    Expanded(
                      child: Stack(
            fit: StackFit.expand,
            children: [
              // ── 1. Camera with Center Stage animation ──────────────────
              Positioned(
                top: 0,
                left: 0,
                right: showSidebar ? sidebarW : 0,
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
                        tween: AlignmentTween(
                            begin: Alignment.center, end: targetAlignment),
                        builder: (context, alignment, innerChild) {
                          return Transform(
                            alignment: alignment,
                            transform: Matrix4.identity()..scale(scale, scale),
                            child: innerChild,
                          );
                        },
                        child: child,
                      );
                    },
                    child: cameraWidget,
                  ),
                ),
              ),

              // ── 2. Bounding Box Overlay ────────────────────────────────
              if (_showBoundingBoxes)
                Positioned(
                  top: 0,
                  left: 0,
                  right: showSidebar ? sidebarW : 0,
                  bottom: controlBarH,
                  child: CustomPaint(
                    painter: BoundingBoxPainter(
                      data: _latestTrackingResult,
                      mode: _currentMode,
                      scaleOffset: S,
                      alignOffset: targetAlignment,
                    ),
                  ),
                ),

              // Removed duplicated Top Status bar since we moved it above the Row

              // ── 4. Right HUD Sidebar ───────────────────────────────────
              if (showSidebar)
                Positioned(
                  top: 0,
                  right: 0,
                  width: sidebarW,
                  bottom: controlBarH,
                  child: _HudSidebar(
                    isConnected: _isConnected,
                    detectedCount: _detectedCount,
                    zoom: _zoomLabel,
                    fps: _currentFps,
                    mode: _currentMode,
                    hasTarget: _targetScale > 1.05,
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
                  availableDevices: _availableDevices,
                  selectedDevice: _selectedDevice,
                  onDeviceSelected: _onDeviceSelected,
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

  Widget _buildLeftSidebar() {
    return Container(
      width: 240,
      color: AfsTheme.surfaceLowest,
      child: Column(
        children: [
          const SizedBox(height: 24),
          _NavSidebarItem(icon: Icons.dashboard_rounded, label: 'DASHBOARD', isActive: true),
          _NavSidebarItem(icon: Icons.videocam_rounded, label: 'CAMERAS'),
          _NavSidebarItem(icon: Icons.location_on_rounded, label: 'WAYPOINTS'),
          _NavSidebarItem(icon: Icons.show_chart_rounded, label: 'TIMELINE'),
          _NavSidebarItem(icon: Icons.upload_rounded, label: 'EXPORT'),
          const Spacer(),
          // Operator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AfsTheme.neonGreen,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('01', style: AfsTheme.monoSmall(AfsTheme.onPrimaryFixed)),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OPERATOR_01', style: AfsTheme.monoSmall(AfsTheme.ashGray)),
                    Text('SYSTEM_ACTIVE', style: AfsTheme.monoSmall(AfsTheme.neonGreen).copyWith(fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Top Status Bar ────────────────────────────────────────────────────────────
class _TopStatusBar extends StatelessWidget {
  final bool isConnected;
  final TrackingMode mode;
  final double fps;
  final VoidCallback? onSettings;
  final VoidCallback? onLogout;

  const _TopStatusBar({
    required this.isConnected,
    required this.mode,
    required this.fps,
    this.onSettings,
    this.onLogout,
  });

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
              // App branding
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isConnected ? AfsTheme.neonGreen : AfsTheme.errorColor,
                  shape: BoxShape.circle,
                  boxShadow: isConnected
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
                  style: AfsTheme.bodySmall(AfsTheme.ashGray.withValues(alpha: 0.5))),

              const Spacer(),

              // FPS badge
              if (fps > 0) ...[
                _StatusBadge(
                  label: '${fps.toStringAsFixed(1)} fps',
                  color: AfsTheme.infoColor,
                ),
                const SizedBox(width: 8),
              ],

              // Connection status
              _StatusBadge(
                label: isConnected ? 'CONNECTED' : 'DISCONNECTED',
                color: isConnected ? AfsTheme.neonGreen : AfsTheme.errorColor,
              ),

              const SizedBox(width: 8),

              // Settings button
              if (onSettings != null)
                GestureDetector(
                  onTap: onSettings,
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
              if (onLogout != null)
                GestureDetector(
                  onTap: onLogout,
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

  const _HudSidebar({
    required this.isConnected,
    required this.detectedCount,
    required this.zoom,
    required this.fps,
    required this.mode,
    required this.hasTarget,
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
                valueColor: hasTarget
                    ? AfsTheme.neonGreen
                    : AfsTheme.ashGray.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 10),

              HudStatTile(
                label: 'SEND RATE',
                value: fps > 0 ? '${fps.toStringAsFixed(1)} fps' : '—',
                icon: Icons.speed_rounded,
              ),

              const Spacer(),

              // System status strip
              Container(
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
                  ],
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
class _NavSidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  const _NavSidebarItem({required this.icon, required this.label, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: isActive ? AfsTheme.surfaceHigh : Colors.transparent,
        border: Border(
          left: BorderSide(color: isActive ? AfsTheme.neonGreen : Colors.transparent, width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: isActive ? AfsTheme.neonGreen : AfsTheme.ashGray.withAlpha(120)),
          const SizedBox(width: 16),
          Text(label, style: AfsTheme.monoSmall(isActive ? AfsTheme.neonGreen : AfsTheme.ashGray)),
        ],
      ),
    );
  }
}

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
      ..strokeWidth = 2.5
      ..color = AfsTheme.neonGreen;

    final otherPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
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
