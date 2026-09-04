import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Central typography scale for Aspire Lock, so every screen shares
/// consistent font sizes/weights instead of ad-hoc TextStyles.
///
/// Two typefaces, each doing one job:
/// - Sora (geometric, technical) carries every word of UI copy —
///   headings, body, labels.
/// - JetBrains Mono is reserved for numbers that are actually data:
///   scheduled times, streak counts, stat figures. Monospace digits
///   line up in a column and read as measurements rather than prose,
///   which fits an app built entirely around schedules and counts.
///   It's applied at the call site (see [mono]), not baked into every
///   style, since most text on screen is still words, not numbers.
///
/// These are getters, not consts — they read from [AppColors], which
/// now switches with dark mode (see app_colors.dart / theme_controller.dart).
/// Any widget that previously wrapped one of these in `const` had that
/// `const` removed app-wide as part of the same change, since a getter
/// can never be a compile-time constant.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle get h1 => GoogleFonts.sora(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.2,
        letterSpacing: -0.5,
      );

  static TextStyle get h2 => GoogleFonts.sora(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.25,
        letterSpacing: -0.3,
      );

  static TextStyle get h3 => GoogleFonts.sora(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get body => GoogleFonts.sora(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.4,
      );

  static TextStyle get bodyMuted => GoogleFonts.sora(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.4,
      );

  static TextStyle get caption => GoogleFonts.sora(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: AppColors.textMuted,
      );

  static TextStyle get button => GoogleFonts.sora(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      );

  /// Big stat/streak figures — e.g. "12" day streak, achievement
  /// counts. Monospace so multi-digit numbers don't visually wobble
  /// as they change day to day.
  static TextStyle get statNumber => GoogleFonts.jetBrainsMono(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
      );

  /// Scheduled times ("09:30"), durations, and other small figures
  /// that should read as precise data rather than prose. Apply this
  /// on top of whatever color/weight the surrounding context needs —
  /// it only sets the typeface and lets digits line up evenly.
  static TextStyle mono({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? AppColors.textSecondary,
      );
}
