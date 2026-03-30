import 'package:flutter/material.dart';

import '../theme.dart';

/// A glassmorphic HUD stat tile showing a single metric.
/// Design: deep green bg, neon green headline value, mono label.
class HudStatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;

  const HudStatTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveValueColor = valueColor ?? AfsTheme.neonGreen;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AfsTheme.deepGreen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AfsTheme.outlineGhost, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: AfsTheme.neonGreen.withValues(alpha: 0.8)),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: AfsTheme.monoSmall(const Color(0xFF85967C)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AfsTheme.headlineLarge(effectiveValueColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
