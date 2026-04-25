import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Read-only chip in the stress-tests screen top bar showing the active
/// `maxFailedHeartbeats` tolerance. Tapping pops back to the connection
/// screen, where the user can change the value via [ToleranceControl].
class ToleranceIndicator extends StatelessWidget {
  final int maxFailedHeartbeats;

  const ToleranceIndicator({super.key, required this.maxFailedHeartbeats});

  String get _label => switch (maxFailedHeartbeats) {
        1 => 'Strict',
        3 => 'Tolerant',
        5 => 'Very tolerant',
        final n => '$n',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4F7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tolerance: $_label',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF596064),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 14,
              color: Color(0xFF596064),
            ),
          ],
        ),
      ),
    );
  }
}
