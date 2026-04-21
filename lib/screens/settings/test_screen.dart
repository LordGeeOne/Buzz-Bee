import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/nexaryo_colors.dart';

/// Empty placeholder used by the Settings screen entry.
class TestScreen extends StatelessWidget {
  const TestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        iconTheme: IconThemeData(color: c.textPrimary),
        title: Text(
          'Test',
          style: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
      ),
      body: Center(
        child: Text(
          'Empty test screen',
          style: GoogleFonts.montserrat(fontSize: 14, color: c.textDim),
        ),
      ),
    );
  }
}
