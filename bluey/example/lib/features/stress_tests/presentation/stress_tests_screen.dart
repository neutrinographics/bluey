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
        // Done bar above the soft keyboard. Lives in the
        // bottomNavigationBar slot rather than inside the body Stack
        // because Scaffold lays the bottomNavigationBar out *above*
        // the keyboard automatically — and the body's MediaQuery has
        // viewInsets.bottom zeroed out (Scaffold consumes the inset
        // to resize the body), which would otherwise make a Stack-
        // positioned bar invisible. The widget self-hides when no
        // field is focused.
        bottomNavigationBar: const _KeyboardDoneBar(),
        // Tap anywhere outside an interactive widget to dismiss the
        // keyboard. Translucent so child gestures (run, stop, help
        // buttons, scroll) still claim their taps; this only fires for
        // taps that land on otherwise-inert background area. Required
        // on iOS where the number pad has no Done key.
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Stack(
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
                    peerSilenceTimeout: settings.peerSilenceTimeout,
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

// ─── Keyboard Done bar ───────────────────────────────────────────────────────

/// A "Done" button that appears just above the soft keyboard when any
/// text field on this screen is focused. Required because iOS's
/// number-pad keyboard has no built-in Done / action button, so without
/// an explicit dismissal control the user has no obvious way to confirm
/// their input and close the keyboard. Tapping outside any widget also
/// dismisses (see the Scaffold body's GestureDetector), but this gives a
/// visible affordance.
///
/// Mounted as `Scaffold.bottomNavigationBar` so the Scaffold lays it out
/// above the keyboard automatically. Visibility is driven by
/// [FocusManager] rather than [MediaQuery]'s `viewInsets.bottom`: the
/// Scaffold consumes the bottom inset to resize the body, so any
/// `MediaQuery` lookup from inside the body sees `viewInsets.bottom == 0`
/// and would never detect the keyboard. Listening to focus changes on
/// the [FocusManager] singleton sidesteps that.
class _KeyboardDoneBar extends StatefulWidget {
  const _KeyboardDoneBar();

  @override
  State<_KeyboardDoneBar> createState() => _KeyboardDoneBarState();
}

class _KeyboardDoneBarState extends State<_KeyboardDoneBar> {
  bool _editingText = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    // On Flutter mobile, only text fields take *persistent* focus —
    // buttons may briefly attach focus during a tap but it's released
    // immediately, so checking for `hasPrimaryFocus` is a reliable
    // proxy for "the soft keyboard is up." Trying to inspect the
    // focused widget's runtime type doesn't work reliably because
    // FocusNode.context points to the surrounding `Focus` widget, not
    // the `EditableText` that ultimately bound it.
    final hasFocus =
        FocusManager.instance.primaryFocus?.hasPrimaryFocus ?? false;
    if (hasFocus != _editingText) {
      setState(() => _editingText = hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_editingText) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          border: Border(
            top: BorderSide(color: Color(0xFFE2E8F0), width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () =>
                FocusManager.instance.primaryFocus?.unfocus(),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF3F6187),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(
              'Done',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
