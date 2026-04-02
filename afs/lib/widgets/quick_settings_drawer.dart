import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../screens/settings_screen.dart';

class QuickSettingsDrawer extends StatefulWidget {
  const QuickSettingsDrawer({super.key});

  @override
  State<QuickSettingsDrawer> createState() => _QuickSettingsDrawerState();
}

class _QuickSettingsDrawerState extends State<QuickSettingsDrawer> {
  double _signalBias = 0.5;
  double _panSpeed = 0.7;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      width: 320,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF09090B).withAlpha(220),
              border: Border(
                left: BorderSide(
                  color: AfsTheme.outlineGhost,
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      children: [
                        Icon(Icons.tune_rounded,
                            size: 20, color: AfsTheme.neonGreen),
                        const SizedBox(width: 10),
                        Text('QUICK SETTINGS',
                            style: AfsTheme.monoMedium(AfsTheme.ashGray)),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              size: 20, color: AfsTheme.ashGray.withAlpha(150)),
                          onPressed: () => Navigator.of(context).pop(),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),

                  Divider(height: 1, color: AfsTheme.outlineGhost),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      children: [
                        // TRACKING MODE
                        _DrawerHeader(label: 'TRACKING MODE'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _ModeChip(label: 'SINGLE', isActive: true),
                            const SizedBox(width: 8),
                            _ModeChip(label: 'MULTI', isActive: false),
                            const SizedBox(width: 8),
                            _ModeChip(label: 'ACTION', isActive: false),
                          ],
                        ),

                        const SizedBox(height: 28),

                        // SIGNAL BIAS
                        _DrawerHeader(label: 'SIGNAL BIAS'),
                        const SizedBox(height: 4),
                        _DrawerSlider(
                          value: _signalBias,
                          min: 0.1,
                          max: 1.0,
                          onChanged: (v) => setState(() => _signalBias = v),
                        ),

                        const SizedBox(height: 28),

                        // PAN SPEED
                        _DrawerHeader(label: 'PAN SPEED'),
                        const SizedBox(height: 4),
                        _DrawerSlider(
                          value: _panSpeed,
                          min: 0.1,
                          max: 1.0,
                          onChanged: (v) => setState(() => _panSpeed = v),
                        ),

                        const SizedBox(height: 28),

                        // SCENE PRESET
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _DrawerHeader(label: 'SCENE PRESET'),
                            InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => const SettingsScreen()));
                              },
                              child: Text('Edit',
                                  style: AfsTheme.labelSmall(AfsTheme.neonGreen)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AfsTheme.surfaceHigh,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AfsTheme.outlineGhost),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.video_camera_front_rounded,
                                  size: 16, color: AfsTheme.neonGreen),
                              const SizedBox(width: 12),
                              Text('STUDIO_VLOG',
                                  style: AfsTheme.monoSmall(AfsTheme.ashGray)),
                              const Spacer(),
                              Icon(Icons.keyboard_arrow_down_rounded,
                                  size: 16, color: AfsTheme.ashGray.withAlpha(150)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Footer link to full settings
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AfsTheme.neonGreen.withAlpha(20),
                        foregroundColor: AfsTheme.neonGreen,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AfsTheme.neonGreen.withAlpha(60)),
                        ),
                      ),
                      icon: const Icon(Icons.settings_suggest_rounded, size: 18),
                      label: Text('Full System Settings',
                          style: AfsTheme.labelSmall(AfsTheme.neonGreen)),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const SettingsScreen()));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  final String label;
  const _DrawerHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: AfsTheme.labelSmall(AfsTheme.ashGray.withAlpha(120)));
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool isActive;
  const _ModeChip({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? AfsTheme.neonGreen.withAlpha(25) : AfsTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AfsTheme.neonGreen.withAlpha(80) : AfsTheme.outlineGhost,
          ),
        ),
        child: Text(
          label,
          style: AfsTheme.monoSmall(
            isActive ? AfsTheme.neonGreen : AfsTheme.ashGray.withAlpha(150),
          ),
        ),
      ),
    );
  }
}

class _DrawerSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _DrawerSlider({
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: AfsTheme.neonGreen,
        inactiveTrackColor: AfsTheme.surfaceHigh,
        thumbColor: Colors.white,
        overlayColor: AfsTheme.neonGreen.withAlpha(40),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        trackHeight: 2,
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }
}
