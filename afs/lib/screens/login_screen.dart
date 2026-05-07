import 'package:flutter/material.dart';
import '../theme.dart';
import 'signup_screen.dart';
import '../main.dart' show CameraScreen;
import '../services/auth_service.dart';

/// Matte Obsidian Login Screen (Desktop) — Stitch: a62b41071a5a447f83c047f5b181d193
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService.instance.login(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CameraScreen()),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not connect to backend.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfsTheme.surfaceLowest,
      body: Stack(
        children: [
          // Background watermark
          Positioned(
            left: 32,
            bottom: 32,
            child: Text(
              'AFS',
              style: AfsTheme.displayLarge(
                AfsTheme.surfaceHigh.withAlpha(60),
              ).copyWith(fontSize: 120),
            ),
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 56,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                children: [
                  // Logo
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AfsTheme.neonGreen.withAlpha(20),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AfsTheme.neonGreen.withAlpha(60)),
                    ),
                    child: const Icon(Icons.center_focus_strong_rounded,
                        size: 18, color: AfsTheme.neonGreen),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AUTO FRAMING',
                          style: AfsTheme.monoSmall(AfsTheme.ashGray)
                              .copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
                      Text('SOFTWARE',
                          style: AfsTheme.monoSmall(
                              AfsTheme.ashGray.withAlpha(100))
                              .copyWith(fontSize: 9)),
                    ],
                  ),
                  const Spacer(),
                  Text('SOFTWARE',
                      style: AfsTheme.monoSmall(
                          AfsTheme.ashGray.withAlpha(80))),
                  const SizedBox(width: 12),
                  Icon(Icons.settings_outlined,
                      size: 16, color: AfsTheme.ashGray.withAlpha(80)),
                ],
              ),
            ),
          ),

          // Center form
          Center(
            child: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('Welcome back',
                          style: AfsTheme.displaySmall(AfsTheme.ashGray)
                              .copyWith(fontSize: 36)),
                      const SizedBox(height: 8),
                      Text('Sign in to continue',
                          style: AfsTheme.bodyMedium(
                              AfsTheme.ashGray.withAlpha(150))),

                      const SizedBox(height: 40),



                      // Email field
                      _LoginField(
                        icon: Icons.mail_outline_rounded,
                        hint: 'Email Address',
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Enter your email'
                            : null,
                      ),
                      const SizedBox(height: 14),

                      // Password field
                      _LoginField(
                        icon: Icons.lock_outline_rounded,
                        hint: 'Password',
                        controller: _passCtrl,
                        obscureText: true,
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Enter your password'
                            : null,
                      ),

                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {},
                          child: Text('Forgot Password?',
                              style: AfsTheme.bodySmall(
                                  AfsTheme.ashGray.withAlpha(150))),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Sign In button  
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _signIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AfsTheme.neonGreen,
                            foregroundColor: AfsTheme.onPrimaryFixed,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          child: _loading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AfsTheme.onPrimaryFixed,
                                  ),
                                )
                              : Text('Sign In',
                                  style: AfsTheme.monoMedium(
                                      AfsTheme.onPrimaryFixed)),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Divider
                      Row(
                        children: [
                          Expanded(
                              child: Divider(
                                  color: AfsTheme.outlineGhost, thickness: 1)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('OR',
                                style: AfsTheme.labelSmall(
                                    AfsTheme.ashGray.withAlpha(100))),
                          ),
                          Expanded(
                              child: Divider(
                                  color: AfsTheme.outlineGhost, thickness: 1)),
                        ],
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => const CameraScreen()),
                          ),
                          icon: const Icon(Icons.videocam_rounded, size: 18),
                          label: Text('Continue as Guest',
                              style: AfsTheme.monoMedium(AfsTheme.neonGreen)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AfsTheme.neonGreen,
                            side: BorderSide(color: AfsTheme.outlineGhost),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Don't have an account? ",
                              style: AfsTheme.bodySmall(
                                  AfsTheme.ashGray.withAlpha(120))),
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const SignUpScreen()),
                            ),
                            child: Text('Create one',
                                style:
                                    AfsTheme.bodySmall(AfsTheme.neonGreen)),
                          ),
                        ],
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

/// Rounded pill-shaped input matching the Stitch Desktop login
class _LoginField extends StatelessWidget {
  final IconData icon;
  final String hint;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _LoginField({
    required this.icon,
    required this.hint,
    required this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AfsTheme.surfaceDim,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AfsTheme.outlineGhost),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        style: AfsTheme.bodyMedium(AfsTheme.ashGray),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AfsTheme.bodyMedium(AfsTheme.ashGray.withAlpha(80)),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 20, right: 12),
            child: Icon(icon, size: 18, color: AfsTheme.neonGreen),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 48),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}
