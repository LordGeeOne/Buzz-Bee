import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../services/device_session_service.dart';
import '../../theme/nexaryo_colors.dart';

class LoginScreen extends StatefulWidget {
  final Future<void> Function()? onSignedIn;

  const LoginScreen({super.key, this.onSignedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final userRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid);
          final existing = await userRef.get();
          final existingData = existing.data() ?? const <String, dynamic>{};
          final existingName = (existingData['name'] as String?)?.trim() ?? '';
          final googleName = user.displayName ?? '';
          // Preserve onboarding-set name; only seed name/nameLower if the
          // user doc has no name yet (first-time sign-in).
          final nameToWrite = existingName.isNotEmpty
              ? existingName
              : googleName;
          final update = <String, dynamic>{
            'email': user.email ?? '',
            'photoURL': user.photoURL ?? '',
            'lastLogin': FieldValue.serverTimestamp(),
          };
          if (existingName.isEmpty && nameToWrite.isNotEmpty) {
            update['name'] = nameToWrite;
            update['nameLower'] = nameToWrite.toLowerCase();
          }
          await userRef.set(update, SetOptions(merge: true));
        } catch (e) {
          debugPrint('Firestore write failed: $e');
        }
        // Stamp this device as the active session for the account. Any
        // other device currently signed in to the same account will see
        // the mismatch on its user-doc snapshot and self-sign-out.
        await DeviceSessionService.instance.claimSession(user.uid);
      }

      if (mounted && widget.onSignedIn != null) {
        await widget.onSignedIn!();
      }
    } catch (e) {
      setState(() => _error = "Couldn't sign you in. Give it another try.");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

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
                    'Welcome',
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
                  child: _buildSignedOut(c),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignedOut(NexaryoColors c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
          'Hey there',
          style: TextStyle(
            fontFamily: 'Beli',
            fontSize: 36,
            height: 1.1,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in to start meeting people',
          style: GoogleFonts.montserrat(fontSize: 14, color: c.textDim),
        ),
        const SizedBox(height: 24),
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.accentWarm),
            ),
            child: Text(
              _error!,
              style: GoogleFonts.montserrat(fontSize: 13, color: c.accentWarm),
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          child: Material(
            color: c.card,
            borderRadius: BorderRadius.circular(34),
            child: InkWell(
              onTap: _isLoading ? null : _signInWithGoogle,
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isLoading)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.primary,
                        ),
                      )
                    else ...[
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedGoogle,
                        color: c.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Continue with Google',
                        style: GoogleFonts.montserrat(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
