import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Added for compute
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:image/image.dart' as img;

// Top level function for Isolate
Future<Uint8List?> _processImageInIsolate(Map<String, dynamic> params) async {
  try {
    final bytes = params['bytes'] as Uint8List;
    
    img.Image? decodedImage = img.decodeImage(bytes);
    if (decodedImage != null) {
      // Encode to high-quality JPG directly without resizing to keep 720p resolution
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
      title: 'AFS Tracking API',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const CameraScreen(),
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
  Map<String, dynamic>? _latestTrackingResult;
  Timer? _frameTimer;
  bool _isProcessingFrame = false;
  bool _isWaitingForServer = false;
  DateTime? _lastSentTime;

  // Auto-framing Target state
  Offset _targetNormalizedCenter = const Offset(0.5, 0.5);
  double _targetScale = 1.0;
  bool _showBoundingBoxes = false;
  bool _isRecording = false;
  bool _isObsActive = false;

  // Device List
  List<dynamic> _availableDevices = [];
  dynamic _selectedDevice; 

  // Backend address (Use 10.0.2.2 for Android emulator, localhost for macOS/iOS sim)
  final String _backendUrl = Platform.isAndroid ? 'ws://10.0.2.2:8000/ws' : 'ws://127.0.0.1:8000/ws';

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
      
      // Tell backend our initial mode
      _sendModeUpdate();
      
      _channel!.stream.listen((message) {
        try {
          final data = jsonDecode(message);
          if (mounted) {
            setState(() {
              _isWaitingForServer = false;
              if (data['type'] == 'recording_ack') {
                _isRecording = data['status'] == 'started';
              } else if (data['type'] == 'obs_ack') {
                _isObsActive = data['status'] == 'started';
              } else if (data['type'] != 'mode_ack') {
                _latestTrackingResult = data;
                _updateAutoFraming(data);
              }
            });
          }
        } catch (e) {
          debugPrint("JSON Parse Error: $e");
        }
      }, onDone: () {
        debugPrint("WebSocket disconnected");
        if (mounted) setState(() { _isConnected = false; _isWaitingForServer = false; });
        // Try to reconnect?
        Future.delayed(const Duration(seconds: 3), _connectWebSocket);
      }, onError: (error) {
        debugPrint("WebSocket Error: $error");
        if (mounted) setState(() { _isConnected = false; _isWaitingForServer = false; });
      });
    } catch (e) {
      debugPrint("Could not connect to WebSocket: \$e");
    }
  }

  void _sendModeUpdate() {
    if (_isConnected && _channel != null) {
      final payload = jsonEncode({
        "mode": _currentMode.name,
      });
      _channel!.sink.add(payload);
    }
  }

  void _toggleRecording() {
    if (_isConnected && _channel != null) {
      final payload = jsonEncode({
        "command": _isRecording ? "stop_recording" : "start_recording",
      });
      _channel!.sink.add(payload);
    }
  }

  void _toggleObs() {
    if (_isConnected && _channel != null) {
      final payload = jsonEncode({
        "command": _isObsActive ? "stop_obs" : "start_obs",
      });
      _channel!.sink.add(payload);
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
                targetRect = Rect.fromLTRB(b['x1'].toDouble(), b['y1'].toDouble(), b['x2'].toDouble(), b['y2'].toDouble());
                break; 
            }
         }
      } else if (_currentMode == TrackingMode.multi && data['aggregate_box'] != null) {
         var ab = data['aggregate_box'];
         targetRect = Rect.fromLTRB(ab['x1'].toDouble(), ab['y1'].toDouble(), ab['x2'].toDouble(), ab['y2'].toDouble());
      }

      if (targetRect != null && fw > 0 && fh > 0) {
          double ncx = targetRect.center.dx / fw;
          double ncy = targetRect.center.dy / fh;
          double nW = targetRect.width / fw;
          double nH = targetRect.height / fh;

          // To perfectly center the bounding box, the alignment will be:
          double alignX = (ncx * 2.0) - 1.0;
          double alignY = (ncy * 2.0) - 1.0;

          // Target bounding box area occupation
          double maxDim = (nW > nH ? nW : nH);
          
          // Add padding around the target so it doesn't fill the whole screen tightly
          double paddingFactor = 2.0; 
          double targetS = 1.0 / (maxDim * paddingFactor); 
          
          // To center the box near the edges without showing black bars, we need to zoom in MORE
          // Formula: S >= 1.0 / (1.0 - |align|)
          double minSx = 1.0;
          if (alignX.abs() < 0.95) minSx = 1.0 / (1.0 - alignX.abs());
          
          double minSy = 1.0;
          if (alignY.abs() < 0.95) minSy = 1.0 / (1.0 - alignY.abs());

          if (minSx > targetS) targetS = minSx;
          if (minSy > targetS) targetS = minSy;

          targetS = targetS.clamp(1.0, 3.5); // Allow zooming in up to 3.5x
          
          // Apply a deadzone threshold to prevent micro-jitters ("pulsing")
          if ((targetS - _targetScale).abs() > 0.05) {
             _targetScale = targetS;
          }
          if ((ncx - _targetNormalizedCenter.dx).abs() > 0.03 || (ncy - _targetNormalizedCenter.dy).abs() > 0.03) {
             _targetNormalizedCenter = Offset(ncx, ncy);
          }
      } else {
          // Reset to default
          _targetNormalizedCenter = const Offset(0.5, 0.5);
          _targetScale = 1.0;
      }
    }
  }

  void _startFrameLoop() {
    // Send a frame every ~500ms (2 FPS) to avoid overloading the WebSocket
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
       if (_lastSentTime != null && DateTime.now().difference(_lastSentTime!).inSeconds > 2) {
           _isWaitingForServer = false; // Watchdog reset
       }

       if (!_isConnected || _isProcessingFrame || !_isCameraInitialized || _isWaitingForServer) return;
       
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
         } else if (_mobileController != null && _mobileController!.value.isInitialized) {
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
         }
       } catch (e) {
         debugPrint("Frame processing error: $e");
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
        List<CameraMacOSDevice> devices = await CameraMacOS.instance.listDevices(
          deviceType: CameraMacOSDeviceType.video,
        );
        setState(() {
          _availableDevices = devices;
          if (devices.isNotEmpty) {
            _selectedDevice = devices.first;
            _initializeMacOSCamera(_selectedDevice);
          }
        });
      } catch (e) {
        debugPrint("Error listing macOS devices: \$e");
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
    setState(() {
      _isCameraInitialized = true; 
    });
    // Frame loop started manually after init
    Future.delayed(const Duration(milliseconds: 1000), _startFrameLoop);
  }

  Future<void> _initializeMobileCamera(CameraDescription camera) async {
    if (_mobileController != null) {
      await _mobileController!.dispose();
    }

    _mobileController = CameraController(
      camera,
      ResolutionPreset.high, 
      enableAudio: false,
    );

    try {
      await _mobileController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
        _startFrameLoop();
      }
    } on CameraException catch (e) {
      debugPrint("Camera initialization error: \$e");
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

  String _getInstructionText() {
    String text = "";
    switch (_currentMode) {
      case TrackingMode.single:
        text = "Single Mode - Tracking specific face";
        break;
      case TrackingMode.multi:
        text = "Multi Mode - Tracking object group";
        break;
    }
    return _isConnected ? "\$text [Connected]" : "\$text [Disconnected]";
  }

  @override
  Widget build(BuildContext context) {
    Widget cameraWidget;
    if (!_isCameraInitialized && !Platform.isMacOS) {
      cameraWidget = const Center(child: CircularProgressIndicator());
    } else if (Platform.isMacOS) {
      cameraWidget = _selectedDevice != null 
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
        : const Center(child: Text("No Camera Selected"));
    } else {
      if (_mobileController != null && _mobileController!.value.isInitialized) {
        cameraWidget = CameraPreview(_mobileController!);
      } else {
         cameraWidget = const Center(child: CircularProgressIndicator());
      }
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 1. Normalization logic for drawing backend coordinates
          // 2. Math for "Center Stage" scale and translation
          
          double W = constraints.maxWidth;
          double H = constraints.maxHeight;
          
          double S = _targetScale;
          double ncx = _targetNormalizedCenter.dx;
          double ncy = _targetNormalizedCenter.dy;
          
          // The FractionalOffset maps (0,0) to top-left and (1,1) to bottom-right.
          // When we scale by S > 1, we want the point (ncx, ncy) to remain in the center of the viewport.
          // The Transform widget requires an alignment origin. Setting the origin to (ncx, ncy) 
          // means scaling will push everything out from that point, keeping it stationary and effectively panning to it!
          
          double alignX = (ncx * 2.0) - 1.0;
          double alignY = (ncy * 2.0) - 1.0;
          
          // Removng the clamp allows the image to pan completely to the edges for tracking
          // even if it means clipping the video frame limits.
          Alignment targetAlignment = Alignment(alignX, alignY);

          return Stack(
            fit: StackFit.expand,
            children: [
              // Animated Container for Smooth Center Stage Panning/Zooming
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 1500),
                curve: Curves.fastOutSlowIn,
                tween: Tween<double>(begin: 1.0, end: S),
                builder: (context, scale, child) {
                  return TweenAnimationBuilder<Alignment>(
                    duration: const Duration(milliseconds: 1500),
                    curve: Curves.fastOutSlowIn,
                    tween: AlignmentTween(begin: Alignment.center, end: targetAlignment),
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    cameraWidget,
                  ],
                ),
              ),
              
              if (_showBoundingBoxes)
                CustomPaint(
                  painter: BoundingBoxPainter(
                    data: _latestTrackingResult,
                    mode: _currentMode,
                    scaleOffset: S,
                    alignOffset: targetAlignment,
                  ),
                ),
              
              // Fixed UI Overlays (Do not scale/pan)
              Positioned(
                bottom: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: Text( 
                    _getInstructionText(), 
                    style: TextStyle(
                      color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 16, 
                      fontWeight: FontWeight.bold,
                      shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ),
              ),

              Positioned(
                bottom: 20,
                left: 20,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: DropdownButton<TrackingMode>(
                        value: _currentMode,
                        dropdownColor: Colors.black87,
                        underline: const SizedBox(),
                        icon: const Icon(Icons.mode_standby, color: Colors.white),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        onChanged: (TrackingMode? newMode) {
                          if (newMode != null) {
                            setState(() {
                              _currentMode = newMode;
                              _latestTrackingResult = null; // Clear old data
                            });
                            _sendModeUpdate();
                          }
                        },
                        items: const [
                          DropdownMenuItem(
                            value: TrackingMode.single,
                            child: Text("Single (Face)"),
                          ),
                          DropdownMenuItem(
                            value: TrackingMode.multi,
                            child: Text("Multi (Group)"),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.crop_square, color: Colors.white, size: 18),
                          Switch(
                            value: _showBoundingBoxes,
                            onChanged: (val) => setState(() => _showBoundingBoxes = val),
                            activeColor: Colors.greenAccent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                        border: Border.all(color: _isRecording ? Colors.redAccent : Colors.white24),
                      ),
                      child: IconButton(
                        icon: Icon(
                          _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                          color: _isRecording ? Colors.redAccent : Colors.white,
                        ),
                        onPressed: _toggleRecording,
                        tooltip: _isRecording ? "Stop Recording" : "Start Recording",
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                        border: Border.all(color: _isObsActive ? Colors.greenAccent : Colors.white24),
                      ),
                      child: IconButton(
                        icon: Icon(
                          _isObsActive ? Icons.cast_connected : Icons.cast,
                          color: _isObsActive ? Colors.greenAccent : Colors.white,
                        ),
                        onPressed: _toggleObs,
                        tooltip: _isObsActive ? "Stop OBS Stream" : "Start OBS Stream",
                      ),
                    ),
                  ],
                ),
              ),

              if (_availableDevices.isNotEmpty)
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: DropdownButton<dynamic>(
                      value: _selectedDevice,
                      dropdownColor: Colors.black87,
                      underline: const SizedBox(), 
                      icon: const Icon(Icons.arrow_drop_up, color: Colors.white),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      onChanged: _onDeviceSelected,
                      items: _availableDevices.map((device) {
                        String name;
                        if (Platform.isMacOS) {
                          name = (device as CameraMacOSDevice).localizedName ?? "Camera \${device.deviceId}";
                        } else {
                          final d = device as CameraDescription;
                          name = "\${d.name} (\${d.lensDirection.name})";
                        }
                        
                        return DropdownMenuItem<dynamic>(
                          value: device,
                          child: Text(
                            name.length > 25 ? "\${name.substring(0, 22)}..." : name,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          );
        },
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
    required this.alignOffset
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data == null || data!['frame_width'] == null || data!['frame_height'] == null) return;
    
    double fw = data!['frame_width'].toDouble();
    double fh = data!['frame_height'].toDouble();
    double sw = size.width;
    double sh = size.height;
    
    // Scale factors to map frame coordinates to screen coordinates
    // Assuming BoxFit.cover, we need to find the actual mapped rect
    double baseScale = [sw / fw, sh / fh].reduce((a, b) => a > b ? a : b);
    double offsetX = (sw - fw * baseScale) / 2;
    double offsetY = (sh - fh * baseScale) / 2;
    
    // Calculate the transformation origin based on Alignment
    // Alignment(-1, -1) = top left (0, 0), Alignment(1, 1) = bottom right (sw, sh)
    double originX = (alignOffset.x + 1.0) / 2.0 * sw;
    double originY = (alignOffset.y + 1.0) / 2.0 * sh;

    Rect mapRect(double x1, double y1, double x2, double y2) {
      // 1. Map to base screen coordinates (BoxFit.cover)
      double bx1 = x1 * baseScale + offsetX;
      double by1 = y1 * baseScale + offsetY;
      double bx2 = x2 * baseScale + offsetX;
      double by2 = y2 * baseScale + offsetY;

      // 2. Apply the dynamic "Center Stage" Transform Matrix translations
      // We scale out from the origin point
      double finalX1 = originX + (bx1 - originX) * scaleOffset;
      double finalY1 = originY + (by1 - originY) * scaleOffset;
      double finalX2 = originX + (bx2 - originX) * scaleOffset;
      double finalY2 = originY + (by2 - originY) * scaleOffset;

      return Rect.fromLTRB(finalX1, finalY1, finalX2, finalY2);
    }

    final targetPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.greenAccent;

    final otherPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.redAccent;

    if (mode == TrackingMode.single && data!['boxes'] != null) {
      for (var b in data!['boxes']) {
        bool isTarget = b['is_target'] == true;
        canvas.drawRect(
          mapRect(b['x1'].toDouble(), b['y1'].toDouble(), b['x2'].toDouble(), b['y2'].toDouble()), 
          isTarget ? targetPaint : otherPaint
        );
      }
    } else if (mode == TrackingMode.multi) {
      if (data!['individual_boxes'] != null) {
        for (var b in data!['individual_boxes']) {
          canvas.drawRect(
            mapRect(b['x1'].toDouble(), b['y1'].toDouble(), b['x2'].toDouble(), b['y2'].toDouble()), 
            otherPaint
          );
        }
      }
      if (data!['aggregate_box'] != null) {
        var ab = data!['aggregate_box'];
        canvas.drawRect(
          mapRect(ab['x1'].toDouble(), ab['y1'].toDouble(), ab['x2'].toDouble(), ab['y2'].toDouble()), 
          targetPaint
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) => true;
}
