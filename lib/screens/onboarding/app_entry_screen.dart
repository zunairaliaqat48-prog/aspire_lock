import 'package:flutter/material.dart';

import '../../database/db_helper.dart';
import '../../constants/app_colors.dart';
import '../main_nav_screen.dart';
import 'welcome_screen.dart';

/// The app's actual `home:` widget in main.dart. Its only job is to
/// check (once, on cold start) whether this device has seen the
/// welcome screen yet, and route to [WelcomeScreen] or straight to
/// [HomeScreen] accordingly. Needed because that check is async
/// (reads the profile row from SQLite) and MaterialApp's `home` can't
/// await anything itself.
class AppEntryScreen extends StatefulWidget {
   AppEntryScreen({super.key});

  @override
  State<AppEntryScreen> createState() => _AppEntryScreenState();
}

class _AppEntryScreenState extends State<AppEntryScreen> {
  @override
  void initState() {
    super.initState();
    _decideDestination();
  }

  Future<void> _decideDestination() async {
    final profile = await DBHelper.instance.getProfile();
    final hasOnboarded = profile?.hasOnboarded ?? false;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            hasOnboarded ? const MainNavScreen() :  WelcomeScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Brief splash shown only for the moment it takes to read the DB.
    return  Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
    );
  }
}
