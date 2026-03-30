import 'package:flutter/material.dart';
import '../theme.dart';
import 'login_screen.dart';

/// Settings (Desktop) — Stitch: 688155d9a50b405aba80e8efe8079a11
/// Top nav bar + operator banner + 3-column grid layout
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Tracking settings
  double _panSensitivity = 0.65;
  double _targetFps = 60;
  bool _hdrMasterOutput = true;
  bool _noiseFloor = true;
  int _resolution = 0; // 0=4K ULTRA, 1=1080P PRO
  int _autoFrameMode = 0; // 0=SOLO_FOCUS, 1=DYNAMIC_GROUP

  // Backend
  final _backendCtrl = TextEditingController(text: 'ws://127.0.0.1:8000/ws');

  int _selectedNav = 0;
  final List<String> _navItems = [
    'LIVE VIEW',
    'ARCHIVE',
    'SENSORS',
    'CALIBRATE'
  ];

  @override
  void dispose() {
    _backendCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfsTheme.surfaceLowest,
      body: Column(
        children: [
          // ── Top Nav Bar ──
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: AfsTheme.surfaceDim,
              border: Border(
                bottom: BorderSide(color: AfsTheme.outlineGhost, width: 1),
              ),
            ),
            child: Row(
              children: [
                Text('AFS',
                    style: AfsTheme.monoMedium(AfsTheme.neonGreen)),
                const SizedBox(width: 32),
                ...List.generate(_navItems.length, (i) {
                  final isActive = _selectedNav == i;
                  return Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: InkWell(
                      onTap: () => setState(() => _selectedNav = i),
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: isActive
                                  ? AfsTheme.neonGreen
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          _navItems[i],
                          style: AfsTheme.monoSmall(
                            isActive
                                ? AfsTheme.ashGray
                                : AfsTheme.ashGray.withAlpha(100),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.person_outline_rounded,
                      size: 18, color: AfsTheme.ashGray),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_none_rounded,
                      size: 18, color: AfsTheme.ashGray),
                  onPressed: () {},
                ),
              ],
            ),
          ),

          // ── Main Content ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                // Operator banner
                Row(
                  children: [
                    // Avatar
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AfsTheme.neonGreen.withAlpha(20),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AfsTheme.neonGreen.withAlpha(60)),
                      ),
                      child: const Icon(Icons.person_rounded,
                          size: 28, color: AfsTheme.neonGreen),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('OPERATOR_01',
                            style: AfsTheme.headlineLarge(AfsTheme.ashGray)),
                        Text('SYSTEM_ACTIVE // OFFSET_2.4',
                            style: AfsTheme.monoSmall(AfsTheme.mintGreen)),
                      ],
                    ),
                    const Spacer(),
                    // Sync config button
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AfsTheme.neonGreen,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('SYNC CONFIG',
                          style: AfsTheme.monoSmall(AfsTheme.onPrimaryFixed)),
                    ),
                    const SizedBox(width: 12),
                    // Logout
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
                            style: AfsTheme.monoSmall(AfsTheme.errorColor)),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // ── 3-Column Grid ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Column 1: VIDEO PIPELINE
                    Expanded(child: _buildVideoPipeline()),
                    const SizedBox(width: 20),
                    // Column 2: KINETIC TRACKING
                    Expanded(child: _buildKineticTracking()),
                    const SizedBox(width: 20),
                    // Column 3: AUDIO ISOLATION
                    Expanded(child: _buildAudioIsolation()),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Bottom Row: Hardware + Presets ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _buildHardware()),
                    const SizedBox(width: 20),
                    Expanded(flex: 4, child: _buildPresets()),
                  ],
                ),

                const SizedBox(height: 28),

                // Footer
                Row(
                  children: [
                    Text('VERSION 2.4.0-STABLE',
                        style: AfsTheme.monoSmall(
                            AfsTheme.ashGray.withAlpha(80))),
                    const SizedBox(width: 24),
                    Text('KERNEL_008_S4',
                        style: AfsTheme.monoSmall(
                            AfsTheme.ashGray.withAlpha(80))),
                    const SizedBox(width: 24),
                    Text('ENCRYPTION: AES-256',
                        style: AfsTheme.monoSmall(
                            AfsTheme.ashGray.withAlpha(80))),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.help_outline_rounded,
                          size: 16, color: AfsTheme.neonGreen),
                      onPressed: () {},
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AfsTheme.neonGreen,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('SAVE CHANGES',
                          style: AfsTheme.monoSmall(AfsTheme.onPrimaryFixed)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Video Pipeline Column ──
  Widget _buildVideoPipeline() {
    return _SectionCard(
      label: 'VIDEO PIPELINE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('STREAM RESOLUTION',
              style: AfsTheme.labelSmall(AfsTheme.ashGray.withAlpha(120))),
          const SizedBox(height: 10),
          Row(
            children: [
              _ToggleChip(
                  label: '4K ULTRA',
                  isActive: _resolution == 0,
                  onTap: () => setState(() => _resolution = 0)),
              const SizedBox(width: 8),
              _ToggleChip(
                  label: '1080P PRO',
                  isActive: _resolution == 1,
                  onTap: () => setState(() => _resolution = 1)),
            ],
          ),
          const SizedBox(height: 20),
          Text('TARGET FPS',
              style: AfsTheme.labelSmall(AfsTheme.ashGray.withAlpha(120))),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('${_targetFps.round()}',
                  style: AfsTheme.monoSmall(AfsTheme.neonGreen)),
              const SizedBox(width: 4),
              Text('FPS', style: AfsTheme.monoSmall(AfsTheme.ashGray.withAlpha(80))),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AfsTheme.neonGreen,
              inactiveTrackColor: AfsTheme.surfaceBright,
              thumbColor: Colors.white,
              overlayColor: AfsTheme.neonGreen.withAlpha(30),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              trackHeight: 2,
            ),
            child: Slider(
              value: _targetFps,
              min: 24,
              max: 120,
              onChanged: (v) => setState(() => _targetFps = v),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('24 FPS', style: AfsTheme.monoSmall(AfsTheme.ashGray.withAlpha(60))),
              Text('60 FPS', style: AfsTheme.monoSmall(AfsTheme.ashGray.withAlpha(60))),
              Text('120 FPS', style: AfsTheme.monoSmall(AfsTheme.ashGray.withAlpha(60))),
            ],
          ),
          const SizedBox(height: 16),
          _InlineToggle(
            label: 'HDR Master Output',
            value: _hdrMasterOutput,
            onChanged: (v) => setState(() => _hdrMasterOutput = v),
          ),
        ],
      ),
    );
  }

  // ── Kinetic Tracking Column ──
  Widget _buildKineticTracking() {
    return _SectionCard(
      label: 'KINETIC TRACKING',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PAN SENSITIVITY',
              style: AfsTheme.labelSmall(AfsTheme.ashGray.withAlpha(120))),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AfsTheme.neonGreen,
              inactiveTrackColor: AfsTheme.surfaceBright,
              thumbColor: Colors.white,
              overlayColor: AfsTheme.neonGreen.withAlpha(30),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              trackHeight: 2,
            ),
            child: Slider(
              value: _panSensitivity,
              min: 0.1,
              max: 1.0,
              onChanged: (v) => setState(() => _panSensitivity = v),
            ),
          ),
          const SizedBox(height: 16),
          Text('AUTO-FRAMING MODE',
              style: AfsTheme.labelSmall(AfsTheme.ashGray.withAlpha(120))),
          const SizedBox(height: 10),
          _RadioOption(
            icon: Icons.person_rounded,
            label: 'SOLO_FOCUS',
            isActive: _autoFrameMode == 0,
            onTap: () => setState(() => _autoFrameMode = 0),
          ),
          const SizedBox(height: 8),
          _RadioOption(
            icon: Icons.group_rounded,
            label: 'DYNAMIC_GROUP',
            isActive: _autoFrameMode == 1,
            onTap: () => setState(() => _autoFrameMode = 1),
          ),
        ],
      ),
    );
  }

  // ── Audio Isolation Column ──
  Widget _buildAudioIsolation() {
    return _SectionCard(
      label: 'AUDIO ISOLATION',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NOISE FLOOR SUPPRESSION',
              style: AfsTheme.labelSmall(AfsTheme.ashGray.withAlpha(120))),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AfsTheme.neonGreen,
              inactiveTrackColor: AfsTheme.surfaceBright,
              thumbColor: Colors.white,
              overlayColor: AfsTheme.neonGreen.withAlpha(30),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              trackHeight: 2,
            ),
            child: Slider(value: 0.7, min: 0, max: 1, onChanged: (v) {}),
          ),
          const SizedBox(height: 16),
          _InlineToggle(
            label: 'Beamforming Mic',
            value: _noiseFloor,
            onChanged: (v) => setState(() => _noiseFloor = v),
          ),
          const SizedBox(height: 8),
          Text('Active: Array_Theta_7',
              style: AfsTheme.monoSmall(AfsTheme.mintGreen)),
          const SizedBox(height: 16),
          Text('SPECTRUM ANALYSIS',
              style: AfsTheme.labelSmall(AfsTheme.neonGreen)),
          const SizedBox(height: 8),
          // Fake spectrum bars
          SizedBox(
            height: 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(16, (i) {
                final h = 10.0 + (i % 5) * 7.0;
                return Expanded(
                  child: Container(
                    height: h,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: AfsTheme.neonGreen.withAlpha(60 + i * 10),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hardware Architecture Section ──
  Widget _buildHardware() {
    return _SectionCard(
      label: 'HARDWARE ARCHITECTURE',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: devices
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HardwareItem(
                  icon: Icons.settings_rounded,
                  name: 'GIMBAL_MK_V',
                  status: 'CONNECTED // 24°C',
                  tag: 'OPTIMAL',
                ),
                const SizedBox(height: 16),
                _HardwareItem(
                  icon: Icons.camera_rounded,
                  name: '35MM_PRIME_LENS',
                  status: 'AUTO_FOCUS_ENGAGED',
                  tag: null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Right: system map placeholder
          Expanded(
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: AfsTheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AfsTheme.outlineGhost),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('SYSTEM MAP',
                      style: AfsTheme.labelSmall(AfsTheme.ashGray.withAlpha(100))),
                  const SizedBox(height: 8),
                  // Fake grid indicator
                  Container(
                    width: 60,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: AfsTheme.neonGreen.withAlpha(60)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: AfsTheme.neonGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Saved Presets Section ──
  Widget _buildPresets() {
    return _SectionCard(
      label: 'SAVED PRESETS',
      child: Column(
        children: [
          _PresetItem(label: 'Cinematic_Slow_Pan', icon: Icons.movie_rounded),
          const SizedBox(height: 8),
          _PresetItem(label: 'Interview_Static', icon: Icons.mic_rounded),
          const SizedBox(height: 8),
          _PresetItem(label: 'Action_Tracking_V3', icon: Icons.speed_rounded),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AfsTheme.outlineGhost),
            ),
            alignment: Alignment.center,
            child: Text('+ CREATE NEW_PROFILE',
                style: AfsTheme.monoSmall(AfsTheme.ashGray.withAlpha(120))),
          ),
        ],
      ),
    );
  }
}

// ── Shared Widgets ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String label;
  final Widget child;
  const _SectionCard({required this.label, required this.child});

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
          Text(label,
              style: AfsTheme.labelSmall(AfsTheme.ashGray.withAlpha(150))),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _ToggleChip(
      {required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AfsTheme.neonGreen.withAlpha(25)
              : AfsTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive
                ? AfsTheme.neonGreen.withAlpha(80)
                : AfsTheme.outlineGhost,
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

class _InlineToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _InlineToggle(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AfsTheme.bodySmall(AfsTheme.ashGray)),
        SizedBox(
          height: 24,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AfsTheme.neonGreen,
            activeTrackColor: AfsTheme.neonGreen.withAlpha(60),
            inactiveThumbColor: AfsTheme.ashGray.withAlpha(100),
            inactiveTrackColor: AfsTheme.surfaceBright,
          ),
        ),
      ],
    );
  }
}

class _RadioOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _RadioOption(
      {required this.icon,
      required this.label,
      required this.isActive,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? AfsTheme.neonGreen.withAlpha(15)
              : AfsTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? AfsTheme.neonGreen.withAlpha(60)
                : AfsTheme.outlineGhost,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color:
                    isActive ? AfsTheme.neonGreen : AfsTheme.ashGray.withAlpha(120)),
            const SizedBox(width: 10),
            Text(label,
                style: AfsTheme.monoSmall(
                  isActive ? AfsTheme.neonGreen : AfsTheme.ashGray,
                )),
          ],
        ),
      ),
    );
  }
}

class _HardwareItem extends StatelessWidget {
  final IconData icon;
  final String name;
  final String status;
  final String? tag;
  const _HardwareItem(
      {required this.icon,
      required this.name,
      required this.status,
      this.tag});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AfsTheme.neonGreen),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: AfsTheme.monoSmall(AfsTheme.ashGray)),
              Text(status, style: AfsTheme.monoSmall(AfsTheme.mintGreen)),
            ],
          ),
        ),
        if (tag != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AfsTheme.neonGreen.withAlpha(20),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AfsTheme.neonGreen.withAlpha(60)),
            ),
            child: Text(tag!, style: AfsTheme.monoSmall(AfsTheme.neonGreen)),
          ),
      ],
    );
  }
}

class _PresetItem extends StatelessWidget {
  final String label;
  final IconData icon;
  const _PresetItem({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AfsTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AfsTheme.outlineGhost),
      ),
      child: Row(
        children: [
          Text(label, style: AfsTheme.monoSmall(AfsTheme.ashGray)),
          const Spacer(),
          Icon(Icons.chevron_right_rounded,
              size: 16, color: AfsTheme.ashGray.withAlpha(80)),
        ],
      ),
    );
  }
}
