import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';
import 'tracking_chip.dart';

/// Glassmorphic bottom control bar — mode chips, record button, bbox toggle.
class AfsControlsBar extends StatelessWidget {
  final TrackingModeSelector modeSelector;
  final bool showBoundingBoxes;
  final ValueChanged<bool> onBoundingBoxToggle;

  // Recording
  final bool isRecording;
  final VoidCallback onRecordToggle;

  // Syphon virtual camera
  final bool isSyphonActive;
  final ValueChanged<bool> onSyphonToggle;

  const AfsControlsBar({
    super.key,
    required this.modeSelector,
    required this.showBoundingBoxes,
    required this.onBoundingBoxToggle,
    required this.isRecording,
    required this.onRecordToggle,
    required this.isSyphonActive,
    required this.onSyphonToggle,
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

              // ── Record Button (centre) ──────────────────────────────────
              _RecordButton(
                isRecording: isRecording,
                onTap: onRecordToggle,
              ),

              const Spacer(),

              // Bounding box toggle
              _GlassToggle(
                icon: Icons.crop_square_rounded,
                label: 'BBOX',
                value: showBoundingBoxes,
                onChanged: onBoundingBoxToggle,
              ),

              const SizedBox(width: 8),

              // Syphon virtual camera toggle
              _GlassToggle(
                icon: Icons.cast_rounded,
                label: 'SYPHON',
                value: isSyphonActive,
                activeColor: const Color(0xFF7C6AF7), // purple accent for Syphon
                onChanged: onSyphonToggle,
              ),

              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pulsing record button — looks like a camera app shutter
class _RecordButton extends StatefulWidget {
  final bool isRecording;
  final VoidCallback onTap;
  const _RecordButton({required this.isRecording, required this.onTap});

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) {
          final scale = widget.isRecording ? _pulseAnim.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.isRecording
                  ? AfsTheme.errorColor.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.6),
              width: 2.5,
            ),
          ),
          padding: const EdgeInsets.all(5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: widget.isRecording
                  ? AfsTheme.errorColor
                  : AfsTheme.errorColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(
                  widget.isRecording ? 6 : 999),
              boxShadow: widget.isRecording
                  ? [
                      BoxShadow(
                        color: AfsTheme.errorColor.withValues(alpha: 0.55),
                        blurRadius: 14,
                        spreadRadius: 2,
                      )
                    ]
                  : [],
            ),
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
  final Color? activeColor; // override accent; defaults to AfsTheme.neonGreen

  const _GlassToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = activeColor ?? AfsTheme.neonGreen;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: value
              ? accent.withValues(alpha: 0.12)
              : AfsTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: value
                ? accent.withValues(alpha: 0.35)
                : AfsTheme.outlineGhost,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: value ? accent : AfsTheme.ashGray.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AfsTheme.labelSmall(
                value ? accent : AfsTheme.ashGray.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
