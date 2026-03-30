import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:camera/camera.dart';
import '../theme.dart';
import 'tracking_chip.dart';

/// Glassmorphic bottom control bar — mode chips, bbox toggle, camera selector.
class AfsControlsBar extends StatelessWidget {
  final TrackingModeSelector modeSelector;
  final bool showBoundingBoxes;
  final ValueChanged<bool> onBoundingBoxToggle;
  final List<dynamic> availableDevices;
  final dynamic selectedDevice;
  final ValueChanged<dynamic> onDeviceSelected;

  const AfsControlsBar({
    super.key,
    required this.modeSelector,
    required this.showBoundingBoxes,
    required this.onBoundingBoxToggle,
    required this.availableDevices,
    required this.selectedDevice,
    required this.onDeviceSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF1C1B1B).withValues(alpha: 0.85),
            border: Border(
              top: BorderSide(
                color: AfsTheme.outlineGhost,
                width: 1,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Mode chips
              ...modeSelector.modes.map((m) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TrackingChip(
                  label: m.label,
                  icon: m.icon,
                  isActive: modeSelector.activeIndex == modeSelector.modes.indexOf(m),
                  onTap: () => modeSelector.onSelect(modeSelector.modes.indexOf(m)),
                ),
              )),

              const Spacer(),

              // Bounding box toggle
              _GlassToggle(
                icon: Icons.crop_square_rounded,
                label: 'BBOX',
                value: showBoundingBoxes,
                onChanged: onBoundingBoxToggle,
              ),

              const SizedBox(width: 12),

              // Camera selector
              if (availableDevices.isNotEmpty)
                _CameraSelector(
                  devices: availableDevices,
                  selected: selectedDevice,
                  onSelected: onDeviceSelected,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Data model for mode selector configuration
class TrackingModeSelector {
  final List<ChipModeItem> modes;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  const TrackingModeSelector({
    required this.modes,
    required this.activeIndex,
    required this.onSelect,
  });
}

class ChipModeItem {
  final String label;
  final IconData icon;
  const ChipModeItem({required this.label, required this.icon});
}

// ── Internal sub-widgets ────────────────────────────────────────────────────

class _GlassToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _GlassToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: value
              ? AfsTheme.neonGreen.withValues(alpha: 0.12)
              : AfsTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: value
                ? AfsTheme.neonGreen.withValues(alpha: 0.35)
                : AfsTheme.outlineGhost,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: value ? AfsTheme.neonGreen : AfsTheme.ashGray.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AfsTheme.labelSmall(
                value ? AfsTheme.neonGreen : AfsTheme.ashGray.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraSelector extends StatelessWidget {
  final List<dynamic> devices;
  final dynamic selected;
  final ValueChanged<dynamic> onSelected;

  const _CameraSelector({
    required this.devices,
    required this.selected,
    required this.onSelected,
  });

  String _deviceName(dynamic device) {
    if (Platform.isMacOS) {
      final d = device as CameraMacOSDevice;
      final name = d.localizedName ?? 'Camera ${d.deviceId}';
      return name.length > 28 ? '${name.substring(0, 25)}...' : name;
    } else {
      final d = device as CameraDescription;
      return '${d.name} (${d.lensDirection.name})';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AfsTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AfsTheme.outlineGhost),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<dynamic>(
          value: selected,
          dropdownColor: AfsTheme.surfaceHighest,
          icon: Icon(Icons.keyboard_arrow_up_rounded,
              size: 18, color: AfsTheme.ashGray.withValues(alpha: 0.7)),
          style: AfsTheme.bodySmall(AfsTheme.ashGray),
          onChanged: onSelected,
          items: devices.map((device) {
            return DropdownMenuItem<dynamic>(
              value: device,
              child: Text(_deviceName(device)),
            );
          }).toList(),
        ),
      ),
    );
  }
}
