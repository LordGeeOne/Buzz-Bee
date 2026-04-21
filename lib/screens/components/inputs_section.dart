import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../theme/nexaryo_colors.dart';
import '../../widgets/section_header.dart';

class InputsSection extends StatefulWidget {
  const InputsSection({super.key});

  @override
  State<InputsSection> createState() => _InputsSectionState();
}

class _InputsSectionState extends State<InputsSection> {
  double _sliderValue = 0.6;
  bool _switchValue = true;
  bool _checkboxValue = true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Inputs',
            description:
                'Form fields and input controls styled for the Nexaryo theme.',
          ),

          // Text Field
          _label('Text Field'),
          const SizedBox(height: 12),
          _styledTextField(hint: 'Enter text...'),
          const SizedBox(height: 24),

          // Search Bar
          _label('Search Bar'),
          const SizedBox(height: 12),
          _styledTextField(
            hint: 'Search...',
            prefixIcon: HugeIcons.strokeRoundedSearch01,
          ),
          const SizedBox(height: 24),

          // Slider
          _label('Slider'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: c.cardBorder),
            ),
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: c.primary,
                inactiveTrackColor: c.cardBorder,
                thumbColor: c.primary,
                overlayColor: c.primary.withValues(alpha: 0.15),
                trackHeight: 4,
              ),
              child: Slider(
                value: _sliderValue,
                onChanged: (v) => setState(() => _sliderValue = v),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Switch
          _label('Switch'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: c.cardBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Toggle option',
                  style: GoogleFonts.montserrat(
                    color: c.textPrimary,
                    fontSize: 14,
                  ),
                ),
                Switch(
                  value: _switchValue,
                  onChanged: (v) => setState(() => _switchValue = v),
                  activeColor: c.primary,
                  inactiveTrackColor: c.cardBorder,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Checkbox
          _label('Checkbox'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: c.cardBorder),
            ),
            child: CheckboxListTile(
              value: _checkboxValue,
              onChanged: (v) => setState(() => _checkboxValue = v ?? false),
              title: Text(
                'Checkbox option',
                style: GoogleFonts.montserrat(
                  color: c.textPrimary,
                  fontSize: 14,
                ),
              ),
              activeColor: c.primary,
              checkColor: Colors.white,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _label(String text) {
    final c = context.colors;
    return Text(
      text,
      style: GoogleFonts.montserrat(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
    );
  }

  Widget _styledTextField({
    required String hint,
    List<List<dynamic>>? prefixIcon,
  }) {
    final c = context.colors;
    return TextField(
      style: GoogleFonts.montserrat(color: c.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.montserrat(color: c.textDim, fontSize: 14),
        prefixIcon: prefixIcon != null
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: HugeIcon(icon: prefixIcon, color: c.textDim, size: 20),
              )
            : null,
        filled: true,
        fillColor: c.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 24,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(34),
          borderSide: BorderSide(color: c.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(34),
          borderSide: BorderSide(color: c.primary),
        ),
      ),
    );
  }
}
