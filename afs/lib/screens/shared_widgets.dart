import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

/// AFS shared scalable layout wrapper — constrains mobile-style content
/// to a comfortable reading width while filling the macOS window.
class AfsScaffold extends StatelessWidget {
  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final bool showBackButton;

  const AfsScaffold({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfsTheme.surfaceDim,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle radial gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.3),
                radius: 1.4,
                colors: [Color(0xFF0E1F0E), AfsTheme.surfaceDim],
              ),
            ),
          ),
          // Content
          SafeArea(
            child: Column(
              children: [
                if (title != null || showBackButton || (actions != null))
                  _AfsTopBar(
                    title: title,
                    showBackButton: showBackButton,
                    actions: actions,
                  ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: child,
                    ),
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

class _AfsTopBar extends StatelessWidget {
  final String? title;
  final bool showBackButton;
  final List<Widget>? actions;

  const _AfsTopBar({this.title, this.showBackButton = false, this.actions});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: AfsTheme.surfaceLow.withAlpha(220),
            border: Border(
              bottom: BorderSide(color: AfsTheme.outlineGhost, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              if (showBackButton)
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AfsTheme.surfaceHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: 14, color: AfsTheme.ashGray),
                  ),
                ),
              if (showBackButton && title != null) const SizedBox(width: 12),
              if (title != null)
                Text(title!, style: AfsTheme.monoMedium(AfsTheme.neonGreen)),
              const Spacer(),
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Neon green pill button — primary CTA
class AfsPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final IconData? icon;

  const AfsPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AfsTheme.neonGreen, AfsTheme.neonGreenDim],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: AfsTheme.neonGreen.withAlpha(80),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF053900),
                ),
              )
            else ...[
              if (icon != null) ...[
                Icon(icon, size: 18, color: const Color(0xFF053900)),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF053900),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Secondary ghost button
class AfsSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  const AfsSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: AfsTheme.charcoal,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AfsTheme.outlineGhost),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AfsTheme.mintGreen),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AfsTheme.mintGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// AFS text field with neon green focus ring
class AfsTextField extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType keyboardType;
  final IconData? prefixIcon;
  final String? Function(String?)? validator;

  const AfsTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.prefixIcon,
    this.validator,
  });

  @override
  State<AfsTextField> createState() => _AfsTextFieldState();
}

class _AfsTextFieldState extends State<AfsTextField> {
  bool _obscure = false;

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AfsTheme.labelSmall(AfsTheme.ashGray.withAlpha(160))),
        const SizedBox(height: 6),
        TextFormField(
          controller: widget.controller,
          obscureText: _obscure,
          keyboardType: widget.keyboardType,
          validator: widget.validator,
          style: GoogleFonts.inter(color: AfsTheme.ashGray, fontSize: 14),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: GoogleFonts.inter(
                color: AfsTheme.ashGray.withAlpha(80), fontSize: 14),
            filled: true,
            fillColor: AfsTheme.surfaceHigh,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            prefixIcon: widget.prefixIcon != null
                ? Icon(widget.prefixIcon,
                    size: 18, color: AfsTheme.ashGray.withAlpha(120))
                : null,
            suffixIcon: widget.obscureText
                ? GestureDetector(
                    onTap: () => setState(() => _obscure = !_obscure),
                    child: Icon(
                      _obscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 18,
                      color: AfsTheme.ashGray.withAlpha(120),
                    ),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AfsTheme.outlineGhost),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AfsTheme.outlineGhost),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  BorderSide(color: AfsTheme.neonGreen.withAlpha(180), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AfsTheme.errorColor),
            ),
          ),
        ),
      ],
    );
  }
}
