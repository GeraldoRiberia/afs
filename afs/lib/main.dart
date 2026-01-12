
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

// Global cache for mobile cameras
late List<CameraDescription> _mobileCameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isMacOS) {
    try {
      _mobileCameras = await availableCameras();
    } on CameraException catch (e) {
      debugPrint('Error: $e.code\nError Message: $e.message');
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
      title: 'AFS Viewfinder',
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
  Rect? _selectionRect;

  // Device List
  List<dynamic> _availableDevices = [];
  dynamic _selectedDevice; // CameraMacOSDevice (mac) or CameraDescription (mobile)

  @override
  void initState() {
    super.initState();
    _initializeCameraList();
  }

  Future<void> _initializeCameraList() async {
    // 1. Check Permissions
    if (!Platform.isMacOS) {
      var status = await Permission.camera.request();
      if (!status.isGranted) return;
    }

    // 2. Fetch Devices
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
        debugPrint("Error listing macOS devices: $e");
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
      _isCameraInitialized = true; // Signal UI to render CameraMacOSView with new ID
    });
  }

  Future<void> _initializeMobileCamera(CameraDescription camera) async {
    if (_mobileController != null) {
      await _mobileController!.dispose();
    }

    _mobileController = CameraController(
      camera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888,
    );

    try {
      await _mobileController!.initialize();
      await _mobileController!.startImageStream((CameraImage image) {
        // Stream processing
      });

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } on CameraException catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  void _onDeviceSelected(dynamic device) {
    if (device == _selectedDevice) return;

    setState(() {
      _selectedDevice = device;
      _isCameraInitialized = false; // Reset init state during switch
    });

    if (Platform.isMacOS) {
      _initializeMacOSCamera(device as CameraMacOSDevice);
    } else {
      _initializeMobileCamera(device as CameraDescription);
    }
  }

  void _handleTap(TapUpDetails details, BoxConstraints constraints) {
    if (!_isCameraInitialized) return;

    final dx = details.localPosition.dx;
    final dy = details.localPosition.dy;
    const double boxSize = 100.0;
    
    setState(() {
      _selectionRect = Rect.fromCenter(
        center: Offset(dx, dy),
        width: boxSize,
        height: boxSize,
      );
    });

    final sensorX = dy / constraints.maxHeight;
    final sensorY = 1.0 - (dx / constraints.maxWidth);
    
    debugPrint("Selected Object at Screen: ($dx, $dy)");
    debugPrint("Approx Sensor Coords (Portrait): ($sensorX, $sensorY)");
  }

  @override
  void dispose() {
    _mobileController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine Viewfinder Widget
    Widget cameraWidget;
    if (!_isCameraInitialized && !Platform.isMacOS) {
      cameraWidget = const Center(child: CircularProgressIndicator());
    } else if (Platform.isMacOS) {
      // MacOS View
      // Note: We Re-create CameraMacOSView when deviceId changes.
      // Ideally we would use a key, but resetting state works safely.
      cameraWidget = _selectedDevice != null 
        ? CameraMacOSView(
            key: ValueKey((_selectedDevice as CameraMacOSDevice).deviceId),
            fit: BoxFit.cover,
            deviceId: (_selectedDevice as CameraMacOSDevice).deviceId,
            cameraMode: CameraMacOSMode.photo,
            enableAudio: false,
            onCameraInizialized: (CameraMacOSController controller) {
              _macOSController = controller;
              // Ensure state is set to fully initialized
              if (!_isCameraInitialized) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  setState(() => _isCameraInitialized = true);
                });
              }
            },
          )
        : const Center(child: Text("No Camera Selected"));
    } else {
      // Mobile View
      if (_mobileController != null && _mobileController!.value.isInitialized) {
        cameraWidget = CameraPreview(_mobileController!);
      } else {
         cameraWidget = const Center(child: CircularProgressIndicator());
      }
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Camera Viewfinder
              cameraWidget,

              // 2. Interaction Layer
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) => _handleTap(details, constraints),
                child: CustomPaint(
                  painter: BoundingBoxPainter(rect: _selectionRect),
                  size: Size.infinite,
                ),
              ),
              
              // 3. UI Overlay - Instructions
              Positioned(
                bottom: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: Text( 
                    "Tap object to track", 
                    style: TextStyle(
                      color: Colors.white.withAlpha(204),
                      fontSize: 16, 
                      fontWeight: FontWeight.bold,
                      shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ),
              ),

              // 4. Camera Selection Dropdown (Bottom Right)
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
                      underline: const SizedBox(), // Hide default underline
                      icon: const Icon(Icons.arrow_drop_up, color: Colors.white),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      onChanged: _onDeviceSelected,
                      items: _availableDevices.map((device) {
                        String name;
                        if (Platform.isMacOS) {
                          name = (device as CameraMacOSDevice).localizedName ?? "Camera ${device.deviceId}";
                        } else {
                          final d = device as CameraDescription;
                          name = "${d.name} (${d.lensDirection.name})";
                        }
                        
                        return DropdownMenuItem<dynamic>(
                          value: device,
                          child: Text(
                            name.length > 25 ? "${name.substring(0, 22)}..." : name,
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
  final Rect? rect;

  BoundingBoxPainter({this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    if (rect == null) return;

    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawRect(rect!, paint);
    
    final centerPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    canvas.drawCircle(rect!.center, 4.0, centerPaint);
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.rect != rect;
  }
}
