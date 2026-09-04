import 'package:flutter/material.dart';
import '../database/db_helper.dart';

/// Single source of truth for whether the app is in dark or light mode.
///
/// This is deliberately NOT a `Theme.of(context)`-based design, because
/// most of the app's existing screens read colors from the static
/// [AppColors] class rather than the widget tree. Making [AppColors]'
/// fields dynamic getters (see app_colors.dart) means they only need
/// one place to check — this controller — and a [ChangeNotifier] at
/// the root of the app (see main.dart's `AnimatedBuilder`) makes sure
/// the whole tree rebuilds with fresh colors when it changes.
class ThemeController extends ChangeNotifier {
  ThemeController._internal();
  static final ThemeController instance = ThemeController._internal();

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  /// Resolved light/dark boolean, taking the OS setting into account
  /// when [mode] is [ThemeMode.system]. [AppColors] reads this.
  bool _resolvedIsDark = false;
  bool get isDark => _resolvedIsDark;

  /// Call once at app startup (see main.dart) to load the user's saved
  /// preference before the first frame, so the app doesn't flash the
  /// wrong theme for a frame.
  Future<void> init() async {
    final saved = await DBHelper.instance.getThemeModeName();
    _mode = _modeFromName(saved);
    _resolveIsDark();
  }

  /// Call whenever the OS-level brightness might have changed (e.g.
  /// from [WidgetsBindingObserver.didChangePlatformBrightness]) so
  /// "System" mode stays in sync without needing app restart.
  void updatePlatformBrightness(Brightness platformBrightness) {
    if (_mode != ThemeMode.system) return;
    final shouldBeDark = platformBrightness == Brightness.dark;
    if (shouldBeDark != _resolvedIsDark) {
      _resolvedIsDark = shouldBeDark;
      notifyListeners();
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    _resolveIsDark();
    await DBHelper.instance.saveThemeModeName(mode.name);
    notifyListeners();
  }

  void _resolveIsDark() {
    switch (_mode) {
      case ThemeMode.dark:
        _resolvedIsDark = true;
        break;
      case ThemeMode.light:
        _resolvedIsDark = false;
        break;
      case ThemeMode.system:
        final platformBrightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        _resolvedIsDark = platformBrightness == Brightness.dark;
        break;
    }
  }

  ThemeMode _modeFromName(String? name) {
    switch (name) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }
}
