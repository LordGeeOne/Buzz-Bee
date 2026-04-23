import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart';
import '../../services/presence_service.dart';
import '../../theme/nexaryo_colors.dart';
import '../dashboard_screen.dart';
import '../splash_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

class SignOutScreen extends StatelessWidget {
  const SignOutScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    await PresenceService.instance.stop();
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn().signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('onboarding_complete');
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => SplashScreen(
          onFinished: () {
            navigatorKey.currentState?.pushReplacement(
              PageRouteBuilder(
                opaque: false,
                pageBuilder: (_, __, ___) => LoginScreen(
                  onSignedIn: () async {
                    final complete = await _isOnboardingComplete();
                    if (complete) {
                      navigatorKey.currentState?.pushReplacement(
                        PageRouteBuilder(
                          opaque: false,
                          pageBuilder: (_, __, ___) => const DashboardScreen(),
                          transitionDuration: const Duration(milliseconds: 800),
                          transitionsBuilder: (_, animation, __, child) =>
                              FadeTransition(opacity: animation, child: child),
                        ),
                      );
                    } else {
                      navigatorKey.currentState?.pushReplacement(
                        PageRouteBuilder(
                          opaque: false,
                          pageBuilder: (_, __, ___) => OnboardingScreen(
                            onComplete: () {
                              navigatorKey.currentState?.pushReplacement(
                                PageRouteBuilder(
                                  opaque: false,
                                  pageBuilder: (_, __, ___) =>
                                      const DashboardScreen(),
                                  transitionDuration: const Duration(
                                    milliseconds: 800,
                                  ),
                                  transitionsBuilder:
                                      (_, animation, __, child) =>
                                          FadeTransition(
                                            opacity: animation,
                                            child: child,
                                          ),
                                ),
                              );
                            },
                          ),
                          transitionDuration: const Duration(milliseconds: 800),
                          transitionsBuilder: (_, animation, __, child) =>
                              FadeTransition(opacity: animation, child: child),
                        ),
                      );
                    }
                  },
                ),
                transitionDuration: const Duration(milliseconds: 800),
                transitionsBuilder: (_, animation, __, child) =>
                    FadeTransition(opacity: animation, child: child),
              ),
            );
          },
        ),
      ),
      (_) => false,
    );
  }

  static Future<bool> _isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('onboarding_complete') == true) return true;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final complete = doc.data()?['onboardingComplete'] == true;
      if (complete) await prefs.setBool('onboarding_complete', true);
      return complete;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Container(
                    height: 68,
                    width: 68,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(34),
                    ),
                    child: IconButton(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowLeft01,
                        color: c.textDim,
                        size: 24,
                      ),
                      iconSize: 24,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Account',
                    style: GoogleFonts.montserrat(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (user?.photoURL != null)
                        CircleAvatar(
                          radius: 40,
                          backgroundImage: NetworkImage(user!.photoURL!),
                        )
                      else
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: c.cardBorder,
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: Center(
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedUser,
                              color: c.textSecondary,
                              size: 36,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Text(
                        user?.displayName ?? 'User',
                        style: const TextStyle(
                          fontFamily: 'Beli',
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        user?.email ?? '',
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          color: c.textDim,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: Material(
                          color: c.card,
                          borderRadius: BorderRadius.circular(34),
                          child: InkWell(
                            onTap: () => _signOut(context),
                            borderRadius: BorderRadius.circular(34),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(34),
                                border: Border.all(color: c.cardBorder),
                              ),
                              child: Center(
                                child: Text(
                                  'Sign Out',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: c.accentWarm,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
