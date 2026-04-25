import 'dart:ui';

import 'package:bluey/bluey.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/di/service_locator.dart';
import '../application/run_burst_write.dart';
import '../application/run_failure_injection.dart';
import '../application/run_mixed_ops.dart';
import '../application/run_mtu_probe.dart';
import '../application/run_notification_throughput.dart';
import '../application/run_soak.dart';
import '../application/run_timeout_probe.dart';
import '../../connection/domain/connection_settings.dart';
import '../../connection/presentation/connection_settings_cubit.dart';
import 'stress_tests_cubit.dart';
import 'stress_tests_state.dart';
import 'widgets/test_card.dart';
import 'widgets/tolerance_indicator.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────

const _kBg = Color(0xFFF7F9FB);
const _kDark = Color(0xFF2C3437);
const _kTopBarTitle = Color(0xFF0F172A);

// ─── Screen ──────────────────────────────────────────────────────────────────

class StressTestsScreen extends StatelessWidget {
  final Connection connection;
  const StressTestsScreen({super.key, required this.connection});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => StressTestsCubit(
        runBurstWrite: getIt<RunBurstWrite>(),
        runMixedOps: getIt<RunMixedOps>(),
        runSoak: getIt<RunSoak>(),
        runTimeoutProbe: getIt<RunTimeoutProbe>(),
        runFailureInjection: getIt<RunFailureInjection>(),
        runMtuProbe: getIt<RunMtuProbe>(),
        runNotificationThroughput: getIt<RunNotificationThroughput>(),
        connection: connection,
      ),
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: [
            BlocBuilder<StressTestsCubit, StressTestsState>(
              builder: (context, state) {
                final top = MediaQuery.of(context).padding.top + 64 + 16;
                final entries = state.cards.entries.toList();
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: SizedBox(height: top)),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final entry = entries[index];
                            final isLast = index == entries.length - 1;
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: isLast ? 128 : 24,
                              ),
                              child: TestCard(
                                test: entry.key,
                                config: entry.value.config,
                                result: entry.value.result,
                                isRunning: entry.value.isRunning,
                                anyRunning: state.anyRunning,
                                onRun: () => context
                                    .read<StressTestsCubit>()
                                    .run(entry.key),
                                onStop: () =>
                                    context.read<StressTestsCubit>().stop(),
                                onConfigChanged: (cfg) => context
                                    .read<StressTestsCubit>()
                                    .updateConfig(entry.key, cfg),
                              ),
                            );
                          },
                          childCount: entries.length,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const _TopBar(),
          ],
        ),
      ),
    );
  }
}

// ─── Top bar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 64 + top,
          color: const Color(0xCCF8FAFC),
          padding: EdgeInsets.only(top: top, left: 8, right: 16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: _kDark, size: 24),
                onPressed: () => Navigator.of(context).pop(),
                padding: const EdgeInsets.all(8),
              ),
              const SizedBox(width: 5),
              Text(
                'Stress Tests',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _kTopBarTitle,
                  letterSpacing: -0.45,
                ),
              ),
              const Spacer(),
              BlocProvider<ConnectionSettingsCubit>.value(
                value: getIt<ConnectionSettingsCubit>(),
                child: BlocBuilder<ConnectionSettingsCubit,
                    ConnectionSettings>(
                  builder: (context, settings) => ToleranceIndicator(
                    maxFailedHeartbeats: settings.maxFailedHeartbeats,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
