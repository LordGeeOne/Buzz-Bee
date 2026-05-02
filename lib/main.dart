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
import 'services/callkit_service.dart';
import 'services/device_session_service.dart';
import 'theme/nexaryo_colors.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings/login_screen.dart';
import 'screens/settings/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'widgets/call_banner_overlay.dart';
import 'widgets/match_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final settings = SettingsProvider();
  final themeProvider = ThemeProvider();
  await Future.wait([settings.load(), themeProvider.load()]);
  await FcmService.instance.start();
  await CallkitService.instance.start();
  // Pre-warm the local device id so it's ready by the time the user signs
  // in (and so the watcher can compare against it without a round-trip).
  await DeviceSessionService.instance.ensureLocalDeviceId();
  if (FirebaseAuth.instance.currentUser != null) {
    PresenceService.instance.start();
    DeviceSessionService.instance.watch(
      FirebaseAuth.instance.currentUser!.uid,
      _handleKickedFromSession,
    );
  }
  // Re-arm / tear-down the watcher whenever auth state changes.
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user == null) {
      DeviceSessionService.instance.stopWatch();
    } else {
      DeviceSessionService.instance.watch(user.uid, _handleKickedFromSession);
    }
  });
  runApp(NexaryoStyleGuide(settings: settings, themeProvider: themeProvider));
}

final navigatorKey = GlobalKey<NavigatorState>();

/// Called when this device's session was superseded by another sign-in.
/// Signs out, returns to the login screen, and shows a brief notice.
Future<void> _handleKickedFromSession() async {
  await PresenceService.instance.stop();
  await DeviceSessionService.instance.signOut();
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  nav.pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => LoginScreen(
        onSignedIn: () async {
          // After re-login, return to the splash entry which routes the user.
          navigatorKey.currentState?.pushReplacement(
            MaterialPageRoute(builder: (_) => const _SplashEntry()),
          );
        },
      ),
    ),
    (_) => false,
  );
  final ctx = nav.overlay?.context ?? nav.context;
  // ignore: use_build_context_synchronously
  ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
    const SnackBar(content: Text('Signed in on another device.')),
  );
}

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
            builder: (context, child) {
              return MatchOverlay(
                child: CallBannerOverlay(
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
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
    // Cold-launched from a lock-screen "Accept" tap → skip splash entirely
    // and let CallkitService push the call screen as soon as the navigator
    // is ready.
    if (CallkitService.instance.pendingIncoming.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final p = CallkitService.instance.pendingIncoming.value;
        if (p == null) return;
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          _goToDashboard();
        }
        CallkitService.instance.pushCallScreen(
          callId: p.callId,
          connectionId: p.connectionId,
          peerUid: p.callerUid,
          peerName: p.callerName,
        );
      });
      return const SizedBox.shrink();
    }
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
