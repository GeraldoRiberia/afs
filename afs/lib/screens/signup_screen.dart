import 'package:flutter/material.dart';
import '../theme.dart';
import 'shared_widgets.dart';
import 'login_screen.dart';
import '../main.dart' show CameraScreen;

/// SignUp (Desktop) — Stitch: 3000c88128914d3995b2e8cb4ee8ed7c
/// Split layout: left hero branding, right form fields
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CameraScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfsTheme.surfaceLowest,
      body: Row(
        children: [
          // ── Left Hero Panel ──
          Expanded(
            flex: 4,
            child: Container(
              color: AfsTheme.surfaceDim,
              padding: const EdgeInsets.all(48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AfsTheme.neonGreen.withAlpha(20),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AfsTheme.neonGreen.withAlpha(60)),
                        ),
                        child: const Icon(Icons.center_focus_strong_rounded,
                            size: 20, color: AfsTheme.neonGreen),
                      ),
                      const SizedBox(width: 12),
                      Text('AFS',
                          style: AfsTheme.monoMedium(AfsTheme.neonGreen)),
                      const SizedBox(width: 8),
                      Text('AUTO FRAMING SOFTWARE',
                          style: AfsTheme.labelSmall(AfsTheme.ashGray.withAlpha(150))),
                    ],
                  ),

                  const Spacer(),

                  // Hero text
                  Text(
                    'Create your\naccount',
                    style: AfsTheme.displayLarge(AfsTheme.ashGray)
                        .copyWith(fontSize: 48, height: 1.1),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 320,
                    child: Text(
                      'Professional AI-powered camera tracking and framing. No operator required.',
                      style: AfsTheme.bodyMedium(AfsTheme.mintGreen),
                    ),
                  ),

                  const Spacer(),

                  // System status
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AfsTheme.neonGreen,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: AfsTheme.neonGreen.withAlpha(120),
                                blurRadius: 8)
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('SYSTEM STATUS: READY',
                          style: AfsTheme.monoSmall(AfsTheme.neonGreen)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Right Form Panel ──
          Expanded(
            flex: 5,
            child: Container(
              color: AfsTheme.surfaceLowest,
              padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 40),

                      AfsTextField(
                        label: 'FULL NAME',
                        hint: 'OPERATOR NAME',
                        controller: _nameCtrl,
                        prefixIcon: Icons.person_outline_rounded,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 20),

                      AfsTextField(
                        label: 'EMAIL ADDRESS',
                        hint: 'SYSTEM@KINETIC.IO',
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: Icons.alternate_email_rounded,
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Enter your email'
                            : null,
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: AfsTextField(
                              label: 'PASSWORD',
                              hint: '••••••••',
                              controller: _passCtrl,
                              obscureText: true,
                              prefixIcon: Icons.lock_outline_rounded,
                              validator: (v) => (v == null || v.length < 8)
                                  ? '8+ characters'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: AfsTextField(
                              label: 'CONFIRM',
                              hint: '••••••••',
                              controller: _confirmCtrl,
                              obscureText: true,
                              prefixIcon: Icons.lock_outline_rounded,
                              validator: (v) => v != _passCtrl.text
                                  ? 'Passwords must match'
                                  : null,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      AfsPrimaryButton(
                        label: 'INITIALIZE PROFILE',
                        icon: Icons.arrow_forward_rounded,
                        onPressed: _createAccount,
                        isLoading: _loading,
                      ),

                      const SizedBox(height: 32),

                      // Security gate divider
                      Row(
                        children: [
                          Expanded(
                              child: Divider(
                                  color: AfsTheme.outlineGhost, thickness: 1)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text('SECURITY GATE',
                                style: AfsTheme.labelSmall(
                                    AfsTheme.ashGray.withAlpha(100))),
                          ),
                          Expanded(
                              child: Divider(
                                  color: AfsTheme.outlineGhost, thickness: 1)),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Social auth buttons
                      _SocialAuthButton(
                        icon: Icons.g_mobiledata_rounded,
                        label: 'SYNC WITH GOOGLE CLOUD',
                      ),
                      const SizedBox(height: 12),
                      _SocialAuthButton(
                        icon: Icons.apple_rounded,
                        label: 'AUTH WITH APPLE ID',
                      ),

                      const SizedBox(height: 28),

                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Already part of the fleet? ',
                                style: AfsTheme.bodySmall(
                                    AfsTheme.ashGray.withAlpha(120))),
                            GestureDetector(
                              onTap: () =>
                                  Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                    builder: (_) => const LoginScreen()),
                              ),
                              child: Text('ACCESS TERMINAL',
                                  style:
                                      AfsTheme.labelSmall(AfsTheme.neonGreen)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialAuthButton extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SocialAuthButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AfsTheme.outlineGhost),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: AfsTheme.ashGray),
          const SizedBox(width: 10),
          Text(label, style: AfsTheme.monoSmall(AfsTheme.ashGray)),
        ],
      ),
    );
  }
}
