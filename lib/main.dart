import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import 'constants/app_colors.dart';
import 'services/notification_service.dart';
import 'services/boot_sync_service.dart';
import 'services/theme_controller.dart';
import 'utils/navigation_service.dart';
import 'screens/onboarding/app_entry_screen.dart';

/// Unique id for the recurring resync alarm (arbitrary but must stay
/// constant across app versions so re-registering it doesn't create
/// a duplicate under a different id).
int _kBootResyncAlarmId = 100001;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must happen before runApp so the very first frame already has the
  // user's saved Light/Dark/System preference — otherwise the app
  // would flash the default theme for a frame on every cold start.
  await ThemeController.instance.init();

  // android_alarm_manager_plus has no iOS implementation — calling it
  // unguarded would crash the app on launch on iOS. Only run this
  // Android-only boot-resync-alarm setup on Android.
  if (Platform.isAndroid) {
    await AndroidAlarmManager.initialize();
    await _scheduleBootResyncAlarm();
  }

  runApp(AspireLockApp());
}

/// Registers a daily alarm (via android_alarm_manager_plus) whose sole
/// job is to re-create pending task alarms from the database. Because
/// it's set with `rescheduleOnReboot: true`, the plugin's own native
/// boot receiver re-registers this alarm automatically after the
/// device restarts — which is what actually makes task alarms survive
/// a reboot (see BootSyncService for why this is needed at all).
Future<void> _scheduleBootResyncAlarm() async {
  await AndroidAlarmManager.periodic(
    Duration(hours: 24),
    _kBootResyncAlarmId,
    BootSyncService.resyncPendingAlarms,
    startAt: DateTime.now().add(Duration(minutes: 1)),
    exact: false,
    wakeup: true,
    rescheduleOnReboot: true,
  );
}

class AspireLockApp extends StatefulWidget {
  AspireLockApp({super.key});

  @override
  State<AspireLockApp> createState() => _AspireLockAppState();
}

class _AspireLockAppState extends State<AspireLockApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // Keeps "System" theme mode in sync live if the user flips their
    // OS-level dark mode while Aspire Lock is open, instead of only
    // picking it up on the next cold start.
    ThemeController.instance.updatePlatformBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  Future<void> _initNotifications() async {
    await NotificationService.instance.init();
    // Handles the case where the app was fully closed and the user
    // opened it by tapping a fired alarm notification.
    await NotificationService.instance.handleColdStartLaunch();
    // Safety net: also resync on a normal foreground launch, not just
    // via the periodic/boot alarm — covers app updates or edge cases
    // where alarms were cleared without a full device reboot.
    await BootSyncService.resyncPendingAlarms();
    // TEMPORARY DEBUG: dumps notification-permission status and every
    // alarm currently registered with Android to the "AspireLockAlarms"
    // log tag on every cold start. See NotificationService.logDiagnostics.
    await NotificationService.instance.logDiagnostics();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole app (and, critically, the ThemeData below —
    // which reads from AppColors' now-dynamic getters) any time
    // ThemeController.instance changes, e.g. the user toggling
    // Light/Dark/System in Settings.
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Aspire Lock',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: ThemeController.instance.mode,
          home: AppEntryScreen(),
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    // AppColors' getters already resolve against
    // ThemeController.instance.isDark, so as long as this method is
    // only ever called from the AnimatedBuilder above (which rebuilds
    // whenever that changes), `theme:` and `darkTheme:` below stay
    // correct for their respective brightness.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      error: AppColors.danger,
      brightness: brightness,
    );

    final baseTextTheme = ThemeData(brightness: brightness).textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      // Applies Sora to every default Material text style (dialogs,
      // menus, tooltips, snackbars) that doesn't get one of the
      // explicit AppTextStyles — so nothing on screen silently falls
      // back to the platform default font.
      textTheme: GoogleFonts.soraTextTheme(baseTextTheme),

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.sora(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          textStyle: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.sora(fontWeight: FontWeight.w600),
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.transparent,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle: GoogleFonts.sora(color: AppColors.textSecondary),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      dividerTheme: DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
      ),
    );
  }
}
