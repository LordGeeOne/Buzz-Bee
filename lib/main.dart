import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'providers/settings_provider.dart';
import 'providers/theme_provider.dart';
import 'services/fcm_service.dart';
import 'services/presence_service.dart';
import 'theme/nexaryo_colors.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings/login_screen.dart';
import 'screens/settings/onboarding_screen.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final settings = SettingsProvider();
  final themeProvider = ThemeProvider();
  await Future.wait([settings.load(), themeProvider.load()]);
  await FcmService.instance.start();
  if (FirebaseAuth.instance.currentUser != null) {
    PresenceService.instance.start();
  }
  runApp(NexaryoStyleGuide(settings: settings, themeProvider: themeProvider));
}

final navigatorKey = GlobalKey<NavigatorState>();

class NexaryoStyleGuide extends StatelessWidget {
  final SettingsProvider settings;
  final ThemeProvider themeProvider;

  const NexaryoStyleGuide({
    super.key,
    required this.settings,
    required this.themeProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Buzz Bee',
            debugShowCheckedModeBanner: false,
            theme: _buildThemeData(theme.lightColors, Brightness.light),
            darkTheme: _buildThemeData(theme.darkColors, Brightness.dark),
            themeMode: theme.themeMode,
            home: const _SplashEntry(),
          );
        },
      ),
    );
  }
}

ThemeData _buildThemeData(NexaryoColors c, Brightness brightness) {
  final base = brightness == Brightness.dark
      ? ThemeData.dark()
      : ThemeData.light();
  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.montserrat(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      iconTheme: IconThemeData(color: c.textPrimary),
    ),
    textTheme: GoogleFonts.montserratTextTheme(base.textTheme),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.primary,
      foregroundColor: Colors.white,
    ),
  );
}

class _SplashEntry extends StatelessWidget {
  const _SplashEntry();

  void _goToDashboard() {
    navigatorKey.currentState?.pushReplacement(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => const DashboardScreen(),
        transitionDuration: const Duration(milliseconds: 800),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _goToOnboarding() {
    navigatorKey.currentState?.pushReplacement(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) =>
            OnboardingScreen(onComplete: () => _goToDashboard()),
        transitionDuration: const Duration(milliseconds: 800),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _goToLogin() {
    navigatorKey.currentState?.pushReplacement(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => LoginScreen(
          onSignedIn: () async {
            PresenceService.instance.start();
            final complete = await _isOnboardingComplete();
            if (complete) {
              _goToDashboard();
            } else {
              _goToOnboarding();
            }
          },
        ),
        transitionDuration: const Duration(milliseconds: 800),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<bool> _isOnboardingComplete() async {
    // Check local cache first
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('onboarding_complete') == true) return true;

    // Check Firestore
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data == null) return false;
      // Treat any of these as proof of completed onboarding so a missing/
      // stale `onboardingComplete` flag doesn't force returning users back
      // through onboarding after a reinstall.
      final flag = data['onboardingComplete'] == true;
      final username = (data['username'] as String?)?.trim();
      final dob = data['dob'];
      final complete =
          flag || (username != null && username.isNotEmpty) || dob != null;
      if (complete) {
        await prefs.setBool('onboarding_complete', true);
      }
      return complete;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SplashScreen(
      onFinished: () async {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          _goToLogin();
        } else {
          final complete = await _isOnboardingComplete();
          if (complete) {
            _goToDashboard();
          } else {
            _goToOnboarding();
          }
        }
      },
    );
  }
}
