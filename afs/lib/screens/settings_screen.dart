import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:camera/camera.dart';
import '../theme.dart';
import 'login_screen.dart';
import '../services/auth_service.dart';
import '../services/config.dart';

class SettingsScreen extends StatefulWidget {
  final List<dynamic> availableDevices;
  final dynamic selectedDevice;
  final ValueChanged<dynamic>? onDeviceSelected;

  final List<dynamic> availableAudioDevices;
  final dynamic selectedAudioDevice;
  final ValueChanged<dynamic>? onAudioDeviceSelected;

  const SettingsScreen({
    super.key,
    this.availableDevices = const [],
    this.selectedDevice,
    this.onDeviceSelected,
    this.availableAudioDevices = const [],
    this.selectedAudioDevice,
    this.onAudioDeviceSelected,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _backendCtrl =
      TextEditingController(text: BackendConfig.wsUrl);
  String? _operatorName;

  late dynamic _localSelectedDevice;
  late dynamic _localSelectedAudio;

  bool get _isMacOSPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    _localSelectedDevice = widget.selectedDevice;
    _localSelectedAudio = widget.selectedAudioDevice;
    _loadOperatorName();
  }

  Future<void> _loadOperatorName() async {
    final name = await AuthService.instance.getCurrentUserName();
    if (!mounted) return;
    setState(() => _operatorName = name);
  }

  @override
  void dispose() {
    _backendCtrl.dispose();
    super.dispose();
  }

  String _videoDeviceName(dynamic device) {
    if (_isMacOSPlatform) {
      final d = device as CameraMacOSDevice;
      return d.localizedName ?? 'Camera ${d.deviceId}';
    } else {
      final d = device as CameraDescription;
      return '${d.name} (${d.lensDirection.name})';
    }
  }

  String _audioDeviceName(dynamic device) {
    if (_isMacOSPlatform) {
      final d = device as CameraMacOSDevice;
      return d.localizedName ?? 'Mic ${d.deviceId}';
    }
    return 'Default';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfsTheme.surfaceLowest,
      body: Column(
        children: [
          // ── Top Bar ──
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AfsTheme.surfaceDim,
              border: Border(
                bottom: BorderSide(color: AfsTheme.outlineGhost, width: 1),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded,
                      size: 18, color: AfsTheme.ashGray),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                const SizedBox(width: 8),
                Text('AFS', style: AfsTheme.monoMedium(AfsTheme.neonGreen)),
                const SizedBox(width: 12),
                Text('SETTINGS',
                    style: AfsTheme.monoSmall(
                        AfsTheme.ashGray.withAlpha(120))),
              ],
            ),
          ),

          // ── Content ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [

                // ── Operator card ───────────────────────────────────────
                _SectionCard(
                  label: 'OPERATOR',
                  icon: Icons.person_outline_rounded,
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AfsTheme.neonGreen.withAlpha(20),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AfsTheme.neonGreen.withAlpha(60)),
                        ),
                        child: const Icon(Icons.person_rounded,
                            size: 24, color: AfsTheme.neonGreen),
                      ),
                      const SizedBox(width: 16),
                          Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _operatorName ?? 'OPERATOR_01',
                            style: AfsTheme.headlineLarge(AfsTheme.ashGray),
                          ),
                          Text('SYSTEM_ACTIVE',
                              style:
                                  AfsTheme.monoSmall(AfsTheme.mintGreen)),
                        ],
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AfsTheme.errorColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: AfsTheme.errorColor.withAlpha(60)),
                          ),
                          child: Text('LOGOUT',
                              style: AfsTheme.monoSmall(
                                  AfsTheme.errorColor)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Backend connection card ─────────────────────────────
                _SectionCard(
                  label: 'BACKEND CONNECTION',
                  icon: Icons.cable_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WEBSOCKET URL',
                          style: AfsTheme.labelSmall(
                              AfsTheme.ashGray.withAlpha(120))),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _backendCtrl,
                        style: AfsTheme.monoSmall(AfsTheme.ashGray),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AfsTheme.surfaceHigh,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: AfsTheme.outlineGhost),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: AfsTheme.outlineGhost),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: AfsTheme.neonGreen.withAlpha(120)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Video Source card ───────────────────────────────────
                if (widget.availableDevices.isNotEmpty)
                  _SectionCard(
                    label: 'VIDEO SOURCE',
                    icon: Icons.videocam_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SELECT CAMERA',
                            style: AfsTheme.labelSmall(
                                AfsTheme.ashGray.withAlpha(120))),
                        const SizedBox(height: 10),
                        _DeviceDropdown(
                          devices: widget.availableDevices,
                          selected: _localSelectedDevice,
                          nameOf: _videoDeviceName,
                          icon: Icons.videocam_outlined,
                          onChanged: (d) {
                            setState(() => _localSelectedDevice = d);
                            widget.onDeviceSelected?.call(d);
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 13,
                                color: AfsTheme.ashGray.withAlpha(80)),
                            const SizedBox(width: 6),
                            Text(
                              'Changes apply immediately to the live feed.',
                              style: AfsTheme.labelSmall(
                                  AfsTheme.ashGray.withAlpha(80)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                if (widget.availableDevices.isNotEmpty)
                  const SizedBox(height: 20),

                // ── Audio Source card ───────────────────────────────────
                _SectionCard(
                  label: 'AUDIO SOURCE',
                  icon: Icons.mic_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SELECT MICROPHONE',
                          style: AfsTheme.labelSmall(
                              AfsTheme.ashGray.withAlpha(120))),
                      const SizedBox(height: 10),
                      if (widget.availableAudioDevices.isNotEmpty)
                        _DeviceDropdown(
                          devices: widget.availableAudioDevices,
                          selected: _localSelectedAudio,
                          nameOf: _audioDeviceName,
                          icon: Icons.mic_none_rounded,
                          onChanged: (d) {
                            setState(() => _localSelectedAudio = d);
                            widget.onAudioDeviceSelected?.call(d);
                          },
                        )
                      else
                        // Mobile / no devices listed
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AfsTheme.surfaceHigh,
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: AfsTheme.outlineGhost),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.mic_none_rounded,
                                  size: 15,
                                  color: AfsTheme.ashGray
                                      .withValues(alpha: 0.5)),
                              const SizedBox(width: 8),
                              Text('System Default',
                                  style: AfsTheme.monoSmall(
                                      AfsTheme.ashGray
                                          .withValues(alpha: 0.6))),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 13,
                              color: AfsTheme.ashGray.withAlpha(80)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                                _isMacOSPlatform
                                  ? 'Audio is captured during recording. Device routing is system-level.'
                                  : 'Uses the device default microphone during recording.',
                              style: AfsTheme.labelSmall(
                                  AfsTheme.ashGray.withAlpha(80)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared Widgets ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Widget child;
  const _SectionCard(
      {required this.label, required this.child, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AfsTheme.surfaceDim,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AfsTheme.outlineGhost),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14,
                    color: AfsTheme.neonGreen.withValues(alpha: 0.6)),
                const SizedBox(width: 8),
              ],
              Text(label,
                  style: AfsTheme.labelSmall(
                      AfsTheme.ashGray.withAlpha(150))),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// Styled dropdown for device selection
class _DeviceDropdown extends StatelessWidget {
  final List<dynamic> devices;
  final dynamic selected;
  final String Function(dynamic) nameOf;
  final IconData icon;
  final ValueChanged<dynamic> onChanged;

  const _DeviceDropdown({
    required this.devices,
    required this.selected,
    required this.nameOf,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AfsTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AfsTheme.outlineGhost),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<dynamic>(
          value: selected,
          isExpanded: true,
          dropdownColor: AfsTheme.surfaceHighest,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: AfsTheme.ashGray.withValues(alpha: 0.6)),
          style: AfsTheme.monoSmall(AfsTheme.ashGray),
          onChanged: (d) {
            if (d != null) onChanged(d);
          },
          items: devices.map((device) {
            final name = nameOf(device);
            return DropdownMenuItem<dynamic>(
              value: device,
              child: Row(
                children: [
                  Icon(icon,
                      size: 14,
                      color: AfsTheme.neonGreen.withValues(alpha: 0.6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
