import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/connection_settings.dart';
import '../connection_settings_cubit.dart';

/// Segmented control on the connection screen that lets the user pick a
/// `peerSilenceTimeout` tolerance for the active connection. Tapping a
/// different segment dispatches `setPeerSilenceTimeout` on the
/// [ConnectionSettingsCubit]; the connection cubit observes that change
/// and triggers a transparent reconnect with the new value.
class ToleranceControl extends StatelessWidget {
  const ToleranceControl({super.key});

  static const _options = [
    (label: 'Strict', value: Duration(seconds: 10)),
    (label: 'Tolerant', value: Duration(seconds: 30)),
    (label: 'Very tolerant', value: Duration(seconds: 60)),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionSettingsCubit, ConnectionSettings>(
      builder: (context, settings) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Heartbeat tolerance',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF596064),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: _options.map((option) {
                final isSelected =
                    settings.peerSilenceTimeout == option.value;
                return Expanded(
                  child: GestureDetector(
                    onTap: isSelected
                        ? null
                        : () => context
                            .read<ConnectionSettingsCubit>()
                            .setPeerSilenceTimeout(option.value),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF3F6187)
                            : const Color(0xFFF0F4F7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        option.label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF596064),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}
