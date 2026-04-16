import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/di/service_locator.dart';
import '../../../shared/domain/uuid_names.dart';
import '../../../shared/presentation/error_snackbar.dart';
import '../../connection/domain/connection_settings.dart';
import '../../connection/presentation/connection_screen.dart';
import '../../connection/presentation/connection_settings_cubit.dart';
import '../application/scan_for_devices.dart';
import '../application/stop_scan.dart';
import '../application/get_bluetooth_state.dart';
import '../application/request_permissions.dart';
import '../application/request_enable.dart';
import 'scanner_cubit.dart';
import 'scanner_state.dart';

// -- Design tokens from Figma --

const _kBackgroundColor = Color(0xFFF7F9FB);
const _kTextDark = Color(0xFF2C3437);
const _kTextMedium = Color(0xFF596064);
const _kTextLight = Color(0xFF747C80);
const _kHeaderText = Color(0xFF0F172A);
const _kSignalStrong = Color(0xFF006D4A);
const _kSignalMedium = Color(0xFF3F6187);
const _kSignalWeak = Color(0xFFA83836);
const _kFabColor = Color(0xFF3F6187);
const _kPillBg = Color(0xFFE3E9ED);

// -- Signal strength --

enum _SignalStrength { strong, medium, weak }

_SignalStrength _signalStrength(int rssi) {
  if (rssi >= -55) return _SignalStrength.strong;
  if (rssi >= -75) return _SignalStrength.medium;
  return _SignalStrength.weak;
}

Color _signalColor(_SignalStrength s) => switch (s) {
  _SignalStrength.strong => _kSignalStrong,
  _SignalStrength.medium => _kSignalMedium,
  _SignalStrength.weak => _kSignalWeak,
};

Color _iconBgColor(_SignalStrength s) => switch (s) {
  _SignalStrength.strong => const Color(0xFF69F6B8),
  _SignalStrength.medium => const Color(0xFFAFD2FD),
  _SignalStrength.weak => const Color(0xFFDCE4E8),
};

int _filledBars(_SignalStrength s) => switch (s) {
  _SignalStrength.strong => 3,
  _SignalStrength.medium => 2,
  _SignalStrength.weak => 1,
};

// -- Scanner Screen --

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (context) => ScannerCubit(
            scanForDevices: getIt<ScanForDevices>(),
            stopScan: getIt<StopScan>(),
            getBluetoothState: getIt<GetBluetoothState>(),
            requestPermissions: getIt<RequestPermissions>(),
            requestEnable: getIt<RequestEnable>(),
          )..initialize(),
      child: const ScaffoldMessenger(child: _ScannerView()),
    );
  }
}

class _ScannerView extends StatelessWidget {
  const _ScannerView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ScannerCubit, ScannerState>(
      listenWhen:
          (previous, current) =>
              previous.error != current.error && current.error != null,
      listener: (context, state) {
        if (state.error != null) {
          ErrorSnackbar.show(context, state.error!);
          context.read<ScannerCubit>().clearError();
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: _kBackgroundColor,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const _TopBar(),
                Expanded(child: _buildContent(state)),
              ],
            ),
          ),
          floatingActionButton: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom,
            ),
            child: _ScanFab(isScanning: state.isScanning),
          ),
        );
      },
    );
  }

  Widget _buildContent(ScannerState state) {
    if (state.bluetoothState == BluetoothState.unauthorized) {
      return const _UnauthorizedState();
    }
    if (state.bluetoothState == BluetoothState.off) {
      return const _BluetoothOffState();
    }
    return _ScannerContent(state: state);
  }
}

// -- Top Bar --

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC).withValues(alpha: 0.8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE2E8F0).withValues(alpha: 0.5),
                offset: const Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              const Icon(Icons.bluetooth, color: _kHeaderText, size: 20),
              const SizedBox(width: 12),
              Text(
                'Bluey',
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _kHeaderText,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.tune,
                  color: _kHeaderText,
                  size: 22,
                ),
                tooltip: 'Connection settings',
                onPressed: () => _showConnectionSettings(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConnectionSettings(BuildContext context) {
    final cubit = getIt<ConnectionSettingsCubit>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return BlocProvider<ConnectionSettingsCubit>.value(
          value: cubit,
          child: const _ConnectionSettingsDialog(),
        );
      },
    );
  }
}

class _ConnectionSettingsDialog extends StatelessWidget {
  const _ConnectionSettingsDialog();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionSettingsCubit, ConnectionSettings>(
      builder: (context, settings) {
        final cubit = context.read<ConnectionSettingsCubit>();
        return AlertDialog(
          title: const Text('Connection settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Max failed heartbeats: ${settings.maxFailedHeartbeats}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Text(
                'Consecutive heartbeat failures that trigger a local '
                'disconnect. Higher values tolerate transient BLE hiccups.',
                style: TextStyle(fontSize: 12, color: Color(0xFF596064)),
              ),
              Slider(
                value: settings.maxFailedHeartbeats.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '${settings.maxFailedHeartbeats}',
                onChanged: (value) =>
                    cubit.setMaxFailedHeartbeats(value.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }
}

// -- Main scanner content --

class _ScannerContent extends StatelessWidget {
  final ScannerState state;

  const _ScannerContent({required this.state});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 120),
      children: [
        _StatusHeroCard(
          isScanning: state.isScanning,
          deviceCount: state.scanResults.length,
        ),
        const SizedBox(height: 32),
        if (state.scanResults.isNotEmpty) ...[
          _SectionHeader(sortMode: state.sortMode),
          const SizedBox(height: 16),
          ...state.scanResults.map(
            (result) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _DeviceCard(result: result),
            ),
          ),
        ] else if (!state.isScanning) ...[
          const _EmptyDeviceHint(),
        ],
      ],
    );
  }
}

// -- Status Hero Card --

class _StatusHeroCard extends StatelessWidget {
  final bool isScanning;
  final int deviceCount;

  const _StatusHeroCard({required this.isScanning, required this.deviceCount});

  @override
  Widget build(BuildContext context) {
    final String title;
    final String subtitle;

    if (isScanning) {
      title = 'Scanning...';
      subtitle =
          'Searching for nearby Bluetooth Low Energy devices using high-fidelity spatial telemetry.';
    } else if (deviceCount > 0) {
      title = '$deviceCount Found';
      subtitle =
          '$deviceCount Bluetooth Low Energy device${deviceCount == 1 ? '' : 's'} discovered nearby.';
    } else {
      title = 'Ready';
      subtitle =
          'Tap the scan button to discover nearby Bluetooth Low Energy devices.';
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 160),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: _kTextDark,
                    letterSpacing: -1.5,
                    height: 1.2,
                  ),
                ),
              ),
              _PulsingDot(isActive: isScanning),
            ],
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: _kTextMedium,
                height: 1.625,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Pulsing dot indicator --

class _PulsingDot extends StatefulWidget {
  final bool isActive;

  const _PulsingDot({required this.isActive});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.isActive) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive ? _kSignalStrong : const Color(0xFF94A3B8);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow:
                widget.isActive
                    ? [
                      BoxShadow(
                        color: color.withValues(
                          alpha: 0.75 * (1 - _controller.value),
                        ),
                        blurRadius: 8 * _controller.value,
                        spreadRadius: 4 * _controller.value,
                      ),
                    ]
                    : null,
          ),
        );
      },
    );
  }
}

// -- Section header --

class _SectionHeader extends StatelessWidget {
  final SortMode sortMode;

  const _SectionHeader({required this.sortMode});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'ACTIVE DISCOVERED PERIPHERALS',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _kTextMedium,
              letterSpacing: 1.2,
            ),
          ),
          PopupMenuButton<SortMode>(
            onSelected:
                (mode) => context.read<ScannerCubit>().setSortMode(mode),
            itemBuilder:
                (context) => [
                  _sortMenuItem(SortMode.signalStrength, 'Signal Strength'),
                  _sortMenuItem(SortMode.name, 'Name'),
                  _sortMenuItem(SortMode.deviceId, 'Device ID'),
                ],
            child: Icon(Icons.sort, size: 16, color: _kTextMedium),
          ),
        ],
      ),
    );
  }

  PopupMenuEntry<SortMode> _sortMenuItem(SortMode mode, String label) {
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          if (sortMode == mode)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.check, size: 16),
            )
          else
            const SizedBox(width: 24),
          Text(label),
        ],
      ),
    );
  }
}

// -- Device Card --

class _DeviceCard extends StatelessWidget {
  final ScanResult result;

  const _DeviceCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final strength = _signalStrength(result.rssi);
    final color = _signalColor(strength);
    final bgColor = _iconBgColor(strength);
    final hasName =
        result.device.name != null && result.device.name!.isNotEmpty;

    return GestureDetector(
      onTap: () => _connectToDevice(context, result.device),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.bluetooth,
                    size: 22,
                    color: _kTextDark.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.device.name ?? 'Unknown Device',
                        style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color:
                              hasName
                                  ? _kTextDark
                                  : _kTextDark.withValues(alpha: 0.6),
                          height: 1.56,
                        ),
                      ),
                      Text(
                        result.device.id.toString(),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: _kTextLight,
                          letterSpacing: 0.55,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                _RssiIndicator(
                  rssi: result.rssi,
                  color: color,
                  strength: strength,
                ),
              ],
            ),
            if (result.advertisement.serviceUuids.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: const Color(0xFFACB3B7).withValues(alpha: 0.1),
                    ),
                  ),
                ),
                padding: const EdgeInsets.only(top: 17),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      result.advertisement.serviceUuids
                          .map((uuid) => _ServicePill(uuid: uuid))
                          .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _connectToDevice(BuildContext context, Device device) async {
    await context.read<ScannerCubit>().stopScan();
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ConnectionScreen(device: device)),
    );
  }
}

// -- RSSI indicator with signal bars --

class _RssiIndicator extends StatelessWidget {
  final int rssi;
  final Color color;
  final _SignalStrength strength;

  const _RssiIndicator({
    required this.rssi,
    required this.color,
    required this.strength,
  });

  @override
  Widget build(BuildContext context) {
    final filled = _filledBars(strength);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$rssi',
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.4,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              'dBm',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: color,
                height: 1.33,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(4, (i) {
            return Container(
              width: 4,
              height: 12,
              margin: EdgeInsets.only(left: i > 0 ? 2 : 0),
              decoration: BoxDecoration(
                color: i < filled ? color : color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(9999),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// -- Service UUID pill --

class _ServicePill extends StatelessWidget {
  final UUID uuid;

  const _ServicePill({required this.uuid});

  @override
  Widget build(BuildContext context) {
    final name = UuidNames.getServiceName(uuid);
    final label = name ?? 'UUID: ${uuid.shortString.toUpperCase()}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _kPillBg,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _kTextMedium,
        ),
      ),
    );
  }
}

// -- Empty state hint --

class _EmptyDeviceHint extends StatelessWidget {
  const _EmptyDeviceHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 48),
          Icon(
            Icons.bluetooth_searching,
            size: 48,
            color: const Color(0xFF94A3B8),
          ),
          const SizedBox(height: 16),
          Text(
            'No devices found',
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _kTextMedium,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap scan to discover nearby devices',
            style: GoogleFonts.inter(fontSize: 14, color: _kTextLight),
          ),
        ],
      ),
    );
  }
}

// -- Permission required state --

class _UnauthorizedState extends StatelessWidget {
  const _UnauthorizedState();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ScannerCubit>();

    return ListView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 120),
      children: [
        _HeroCard(
          title: 'Permission\nRequired',
          subtitle:
              'Bluetooth permission is required to scan for nearby devices.',
          dotColor: _kSignalWeak,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => cubit.requestPermissions(),
          icon: const Icon(Icons.lock_open),
          label: const Text('Grant Permission'),
          style: FilledButton.styleFrom(
            backgroundColor: _kFabColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => cubit.openSettings(),
          icon: const Icon(Icons.settings),
          label: const Text('Open Settings'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kFabColor,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }
}

// -- Bluetooth off state --

class _BluetoothOffState extends StatelessWidget {
  const _BluetoothOffState();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ScannerCubit>();

    return ListView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 120),
      children: [
        _HeroCard(
          title: 'Bluetooth\nis Off',
          subtitle: 'Please enable Bluetooth to scan for nearby devices.',
          dotColor: Colors.orange,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => cubit.requestEnable(),
          icon: const Icon(Icons.bluetooth),
          label: const Text('Enable Bluetooth'),
          style: FilledButton.styleFrom(
            backgroundColor: _kFabColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }
}

// -- Reusable hero card for state displays --

class _HeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color dotColor;

  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 160),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: _kTextDark,
                    letterSpacing: -1.5,
                    height: 1.2,
                  ),
                ),
              ),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: _kTextMedium,
              height: 1.625,
            ),
          ),
        ],
      ),
    );
  }
}

// -- Circular scan FAB --

class _ScanFab extends StatelessWidget {
  final bool isScanning;

  const _ScanFab({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ScannerCubit>();

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isScanning ? _kSignalWeak : _kFabColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 50,
            offset: const Offset(0, 25),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isScanning ? cubit.stopScan : cubit.startScan,
          child: Center(
            child: Icon(
              isScanning ? Icons.stop : Icons.bluetooth_searching,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
