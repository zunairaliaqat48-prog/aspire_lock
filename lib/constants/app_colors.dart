import 'package:flutter/material.dart';
import '../services/theme_controller.dart';

/// Central color palette for Aspire Lock — matches the app icon
/// (charcoal/near-black + amber accent) for consistent branding.
///
/// Every field below is a *getter*, not a const, because it switches
/// between the light and dark palette based on [ThemeController]'s
/// current mode. This lets every existing screen keep writing
/// `AppColors.primary` etc. exactly as before — the only change
/// required elsewhere is that any widget built from these can no
/// longer be declared `const` (see the app-wide const cleanup that
/// went with this change), since the value is no longer known at
/// compile time.
class AppColors {
  AppColors._();

  static bool get _isDark => ThemeController.instance.isDark;

  // Brand colors stay identical in both modes — they're the identity
  // of the app, not something that should wash out at night.
  static const Color accent = Color(0xFFF59E0B); // amber — achievement/streak
  static const Color accentLight = Color(0xFFFBBF24);

  /// A second, distinct signal color reserved for "this is active/
  /// running right now" — the current phase, an in-progress task, a
  /// live countdown. Kept separate from [accent] on purpose: amber
  /// means "you earned this," teal means "this is happening now."
  /// One accent color doing every job reads as decoration; two
  /// accents with different jobs read as a system.
  static const Color pulse = Color(0xFF2DD4BF);

  static Color get primary =>
      _isDark ? const Color(0xFFEDEDEF) : const Color(0xFF1A1A1D);
  static Color get primaryLight =>
      _isDark ? const Color(0xFFD8D8DC) : const Color(0xFF2D2D30);

  static Color get background =>
      _isDark ? const Color(0xFF0C0D10) : const Color(0xFFF7F7F8);
  static Color get surface =>
      _isDark ? const Color(0xFF17181C) : Colors.white;
  static Color get surfaceElevated =>
      _isDark ? const Color(0xFF1E1F24) : Colors.white;

  static Color get textPrimary =>
      _isDark ? const Color(0xFFF2F2F3) : const Color(0xFF1A1A1D);
  static Color get textSecondary =>
      _isDark ? const Color(0xFFA6A6AD) : const Color(0xFF6B7280);
  static Color get textMuted =>
      _isDark ? const Color(0xFF75757D) : const Color(0xFF9CA3AF);

  static Color get success =>
      _isDark ? const Color(0xFF34D058) : const Color(0xFF16A34A);
  static Color get danger =>
      _isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);

  static Color get divider =>
      _isDark ? const Color(0xFF2E2E33) : const Color(0xFFE5E7EB);
  static Color get cardShadow =>
      _isDark ? const Color(0x33000000) : const Color(0x14000000);

  /// On the dark palette, `primary` becomes a light/near-white color
  /// (see above) so it still reads as "the ink color" against a dark
  /// background. But anywhere that colors a *filled* surface (e.g. the
  /// selected GoalCard background, ElevatedButton fill) with
  /// `AppColors.primary`, that logic was written assuming primary is
  /// always dark, with white text on top. Use [onPrimary] for that
  /// text/icon color instead of hardcoding `Colors.white`, so it stays
  /// readable in both modes.
  static Color get onPrimary => _isDark ? const Color(0xFF1A1A1D) : Colors.white;
}
