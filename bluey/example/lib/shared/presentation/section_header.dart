import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _kDark = Color(0xFF2C3437);
const _kLight = Color(0xFF747C80);
const _kBadgeBg = Color(0xFFE3E9ED);
const _kAccent = Color(0xFF3F6187);

/// A reusable section header with a title, optional refresh icon, count badge,
/// and snackbar feedback on refresh.
///
/// Used for "Characteristics" on the service screen and "Services" on the
/// connection screen. The entire right-side (icon + badge) is a single tap
/// target.
class SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool isRefreshing;
  final VoidCallback? onRefresh;

  const SectionHeader({
    super.key,
    required this.title,
    required this.count,
    required this.isRefreshing,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _kDark,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: isRefreshing ? null : onRefresh,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child:
                    isRefreshing
                        ? const CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: _kAccent,
                        )
                        : const Icon(Icons.refresh, color: _kLight, size: 16),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _kBadgeBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${count.toString().padLeft(2, '0')} FOUND',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _kLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
