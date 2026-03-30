import 'package:flutter/material.dart';
import '../theme.dart';

/// A tracking mode selection chip with neon green active state.
class TrackingChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const TrackingChip({
    super.key,
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? AfsTheme.neonGreen.withValues(alpha: 0.15)
              : AfsTheme.charcoal,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive
                ? AfsTheme.neonGreen.withValues(alpha: 0.4)
                : AfsTheme.outlineGhost,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChipIcon(icon: icon, isActive: isActive),
            const SizedBox(width: 8),
            Text(
              label,
              style: AfsTheme.monoMedium(
                isActive ? AfsTheme.neonGreen : AfsTheme.ashGray,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipIcon extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  const _ChipIcon({required this.icon, required this.isActive});
  @override
  State<_ChipIcon> createState() => _ChipIconState();
}

class _ChipIconState extends State<_ChipIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Icon(widget.icon, size: 16, color: AfsTheme.ashGray.withValues(alpha: 0.6));
    }
    return AnimatedBuilder(
      animation: _glow,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AfsTheme.neonGreen.withValues(alpha: _glow.value * 0.7),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(widget.icon, size: 16, color: AfsTheme.neonGreen),
      ),
    );
  }
}
