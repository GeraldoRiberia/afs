import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// AFS Design System Tokens — "Kinetic Aperture" (Stitch Obsidian Kinetic)
///
/// Primary:   #00FF9D   Secondary: #4CAF7A   Tertiary: #00E676
/// Neutral:   #0A0C10   Surface:   #111318
class AfsTheme {
  // ── Surface Hierarchy (Tonal Layering) ─────────────────────────────────────
  static const Color surfaceLowest = Color(0xFF0C0E12);
  static const Color surfaceLow = Color(0xFF1A1C20);
  static const Color surfaceDim = Color(0xFF111318);
  static const Color surfaceContainer = Color(0xFF1E2024);
  static const Color surfaceHigh = Color(0xFF282A2E);
  static const Color surfaceHighest = Color(0xFF333539);
  static const Color surfaceBright = Color(0xFF37393E);
  static const Color surfaceVariant = Color(0xFF333539);

  // ── Primary / Accent ───────────────────────────────────────────────────────
  static const Color neonGreen = Color(0xFF00FF9D); // Primary
  static const Color neonGreenDim = Color(0xFF00E38B); // Primary fixed dim
  static const Color primaryContainer = Color(0xFF00FF9D);
  static const Color onPrimary = Color(0xFF00391F);
  static const Color onPrimaryFixed = Color(0xFF002110);

  // ── Secondary ──────────────────────────────────────────────────────────────
  static const Color secondary = Color(0xFF4CAF7A); // Override secondary
  static const Color secondaryContainer = Color(0xFF047D4D);
  static const Color mintGreen = Color(0xFF77DAA1); // secondary named

  // ── Tertiary ───────────────────────────────────────────────────────────────
  static const Color tertiary = Color(0xFF00E676); // Override tertiary
  static const Color tertiaryContainer = Color(0xFF3EFE8B);

  // ── Neutrals / Text ────────────────────────────────────────────────────────
  static const Color onSurface = Color(0xFFE2E2E8);
  static const Color onSurfaceVariant = Color(0xFFB9CBBC);
  static const Color ashGray = Color(0xFFE2E2E8); // == on_surface
  static const Color charcoal = Color(0xFF1E2024);
  static const Color graphite = Color(0xFF2A2E36);

  // ── Outlines ───────────────────────────────────────────────────────────────
  static const Color outline = Color(0xFF849587);
  static const Color outlineGhost = Color(0xFF3B4A3F); // outline_variant

  // ── Status ─────────────────────────────────────────────────────────────────
  static const Color errorColor = Color(0xFFFFB4AB);
  static const Color errorContainer = Color(0xFF93000A);
  static const Color warningColor = Color(0xFFFFD600);
  static const Color infoColor = Color(0xFF00B0FF);

  // Legacy alias kept for backward-compat
  static const Color deepGreen = Color(0xFF002110);

  // ── Typography ─────────────────────────────────────────────────────────────
  // Headline / Display → Space Grotesk
  // Body              → Inter
  // Labels            → Inter
  static TextStyle get textBase => GoogleFonts.inter(color: ashGray);

  // Display
  static TextStyle displayLarge(Color color) => GoogleFonts.spaceGrotesk(
        fontSize: 56,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -1.5,
      );
  static TextStyle displayMedium(Color color) => GoogleFonts.spaceGrotesk(
        fontSize: 42,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -1,
      );
  static TextStyle displaySmall(Color color) => GoogleFonts.spaceGrotesk(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.5,
      );

  // Headlines
  static TextStyle headlineLarge(Color color) => GoogleFonts.spaceGrotesk(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.5,
      );
  static TextStyle headlineMedium(Color color) => GoogleFonts.spaceGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: color,
      );

  // Body
  static TextStyle bodyLarge(Color color) => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: color,
      );
  static TextStyle bodyMedium(Color color) => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: color,
      );
  static TextStyle bodySmall(Color color) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: color,
      );

  // Mono / Tech readouts (Space Grotesk for that "instrument" feel)
  static TextStyle monoLarge(Color color) => GoogleFonts.spaceGrotesk(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.5,
      );
  static TextStyle monoMedium(Color color) => GoogleFonts.spaceGrotesk(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color,
      );
  static TextStyle monoSmall(Color color) => GoogleFonts.spaceGrotesk(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0.5,
      );

  // Labels (Inter per Stitch spec)
  static TextStyle labelSmall(Color color) => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.8,
      );

  // ── ThemeData ──────────────────────────────────────────────────────────────
  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: surfaceDim,
      colorScheme: const ColorScheme.dark(
        primary: neonGreen,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        secondary: secondary,
        secondaryContainer: secondaryContainer,
        tertiary: tertiary,
        tertiaryContainer: tertiaryContainer,
        surface: surfaceDim,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineGhost,
        error: errorColor,
        errorContainer: errorContainer,
        surfaceContainerHighest: surfaceHighest,
        surfaceContainerHigh: surfaceHigh,
        surfaceContainer: surfaceContainer,
        surfaceContainerLow: surfaceLow,
        surfaceContainerLowest: surfaceLowest,
        surfaceBright: surfaceBright,
        surfaceDim: surfaceDim,
      ),
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: TextTheme(
        displayLarge: displayLarge(ashGray),
        displayMedium: displayMedium(ashGray),
        displaySmall: displaySmall(ashGray),
        headlineLarge: headlineLarge(ashGray),
        headlineMedium: headlineMedium(ashGray),
        bodyLarge: bodyLarge(ashGray),
        bodyMedium: bodyMedium(ashGray),
        bodySmall: bodySmall(mintGreen),
        labelSmall: labelSmall(onSurfaceVariant),
      ),
      iconTheme: const IconThemeData(color: ashGray),
      sliderTheme: SliderThemeData(
        activeTrackColor: neonGreen,
        inactiveTrackColor: surfaceBright,
        thumbColor: Colors.white,
        overlayColor: neonGreen.withAlpha(40),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        trackHeight: 3,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return neonGreen;
          return ashGray.withAlpha(100);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return neonGreen.withAlpha(60);
          }
          return surfaceBright;
        }),
      ),
    );
  }
}
