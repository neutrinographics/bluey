import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart' as bluey;
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/di/service_locator.dart';
import '../../../shared/presentation/error_snackbar.dart';
import '../../../shared/presentation/section_header.dart';
import '../../../shared/domain/uuid_names.dart';
import '../../service_explorer/presentation/service_screen.dart';
import '../../stress_tests/presentation/stress_tests_screen.dart';
import '../../../shared/stress_protocol.dart';
import '../application/connect_to_device.dart';
import '../application/disconnect_device.dart';
import '../application/get_services.dart';
import 'connection_cubit.dart';
import 'connection_settings_cubit.dart';
import 'connection_state.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────

const _kBg = Color(0xFFF7F9FB);
const _kCard = Colors.white;
const _kAccent = Color(0xFF3F6187);
const _kDark = Color(0xFF2C3437);
const _kMid = Color(0xFF596064);
const _kLight = Color(0xFF747C80);
const _kTopBarTitle = Color(0xFF0F172A);
const _kIconBg = Color(0xFFAFD2FD);
const _kUuidBg = Color(0xFFF0F4F7);
const _kGreen = Color(0xFF006D4A);
const _kGreenBg = Color(0x1A006D4A);
const _kRed = Color(0xFFA83836);
const _kRedBg = Color(0x1AA83836);

// ─── Screen ──────────────────────────────────────────────────────────────────

class ConnectionScreen extends StatelessWidget {
  final bluey.Device device;

  const ConnectionScreen({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (context) => ConnectionCubit(
            device: device,
            connectToDevice: getIt<ConnectToDevice>(),
            disconnectDevice: getIt<DisconnectDevice>(),
            getServices: getIt<GetServices>(),
            settingsCubit: getIt<ConnectionSettingsCubit>(),
          )..connect(),
      child: const _ConnectionView(),
    );
  }
}

class _ConnectionView extends StatelessWidget {
  const _ConnectionView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ConnectionCubit, ConnectionScreenState>(
      listenWhen: (previous, current) {
        if (previous.connectionState != bluey.ConnectionState.disconnected &&
            current.connectionState == bluey.ConnectionState.disconnected &&
            current.error != null) {
          return true;
        }
        return previous.error != current.error && current.error != null;
      },
      listener: (context, state) {
        if (state.connectionState == bluey.ConnectionState.disconnected &&
            state.error == 'Device disconnected') {
          _showDisconnectedDialog(context);
        } else if (state.error != null) {
          ErrorSnackbar.show(context, state.error!);
          context.read<ConnectionCubit>().clearError();
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: _kBg,
          body: Stack(
            children: [
              _buildBody(context, state),
              _TopBar(deviceName: state.device.name),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, ConnectionScreenState state) {
    if (state.connectionState == bluey.ConnectionState.connecting) {
      return const _ConnectingState();
    }

    if (state.error != null && !state.connectionState.isConnected) {
      return _ErrorState(error: state.error!);
    }

    if (!state.connectionState.isConnected) {
      return const _DisconnectedState();
    }

    return _ConnectedContent(state: state);
  }

  void _showDisconnectedDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Disconnected',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
            ),
            content: Text(
              'The device has been disconnected.',
              style: GoogleFonts.inter(color: _kMid),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).pop();
                },
                child: Text('OK', style: GoogleFonts.inter(color: _kMid)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  context.read<ConnectionCubit>().connect();
                },
                child: Text(
                  'Reconnect',
                  style: GoogleFonts.inter(
                    color: _kAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
    );
  }
}

// ─── Top Bar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String? deviceName;

  const _TopBar({this.deviceName});

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
              Expanded(
                child: Text(
                  deviceName ?? 'Unknown Device',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _kTopBarTitle,
                    letterSpacing: -0.45,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Connecting state ────────────────────────────────────────────────────────

class _ConnectingState extends StatelessWidget {
  const _ConnectingState();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 64 + 16;

    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 3, color: _kAccent),
            ),
            const SizedBox(height: 24),
            Text(
              'Connecting...',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _kMid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Disconnected state ──────────────────────────────────────────────────────

class _DisconnectedState extends StatelessWidget {
  const _DisconnectedState();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 64 + 16;

    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Center(
        child: Text(
          'Not connected',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: _kLight,
          ),
        ),
      ),
    );
  }
}

// ─── Error state ─────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String error;

  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 64 + 16;
    final cubit = context.read<ConnectionCubit>();

    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: _kRedBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline, size: 32, color: _kRed),
              ),
              const SizedBox(height: 24),
              Text(
                'Connection Failed',
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _kDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: _kRed),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: cubit.connect,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment(-0.7, -0.5),
                      end: Alignment(0.7, 0.5),
                      colors: [Color(0xFF3F6187), Color(0xFF32557A)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _kAccent.withValues(alpha: 0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 10),
                        spreadRadius: -3,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.refresh, size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        'Retry',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
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

// ─── Connected content ───────────────────────────────────────────────────────

class _ConnectedContent extends StatefulWidget {
  final ConnectionScreenState state;

  const _ConnectedContent({required this.state});

  @override
  State<_ConnectedContent> createState() => _ConnectedContentState();
}

class _ConnectedContentState extends State<_ConnectedContent> {
  bool _isRefreshing = false;

  Future<void> _refreshServices() async {
    if (_isRefreshing) return;
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<ConnectionCubit>();
    setState(() => _isRefreshing = true);
    try {
      await cubit.loadServices();
      if (!mounted) return;
      setState(() => _isRefreshing = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Services refreshed'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRefreshing = false);
      messenger.showSnackBar(const SnackBar(content: Text('Refresh failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final top = MediaQuery.of(context).padding.top + 64 + 16;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: top)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverToBoxAdapter(
            child: _DeviceInfoCard(
              device: state.device,
              connection: state.connection!,
              services: state.services,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
            child: SectionHeader(
              title: 'Services',
              count: state.services?.length ?? 0,
              isRefreshing: _isRefreshing || state.isDiscovering,
              onRefresh: _refreshServices,
            ),
          ),
        ),
        if (state.services == null || state.services!.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Text(
                  state.isDiscovering
                      ? 'Discovering services...'
                      : 'No services found',
                  style: GoogleFonts.inter(fontSize: 14, color: _kLight),
                ),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final service = state.services![index];
              final isLast = index == state.services!.length - 1;
              return Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, isLast ? 128 : 12),
                child: _ServiceCard(
                  service: service,
                  onTap: () => _openService(context, service, state),
                ),
              );
            }, childCount: state.services!.length),
          ),
      ],
    );
  }

  void _openService(
    BuildContext context,
    bluey.RemoteService service,
    ConnectionScreenState state,
  ) {
    final cubit = context.read<ConnectionCubit>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => ServiceScreen(
              connection: state.connection!,
              service: service,
              onRefresh: () async {
                await cubit.loadServices();
                final services = cubit.state.services;
                if (services == null) return null;
                try {
                  return services.firstWhere((s) => s.uuid == service.uuid);
                } catch (_) {
                  return null;
                }
              },
            ),
      ),
    );
  }
}

// ─── Device info card ────────────────────────────────────────────────────────

class _DeviceInfoCard extends StatelessWidget {
  final bluey.Device device;
  final bluey.Connection connection;
  final List<bluey.RemoteService>? services;

  const _DeviceInfoCard({
    required this.device,
    required this.connection,
    this.services,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: _kIconBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bluetooth_connected,
                  color: _kAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name ?? 'Unknown Device',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _kDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _kGreenBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Connected',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _kGreen,
                            ),
                          ),
                        ),
                        if (connection.isBlueyServer) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1D4ED8),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'BLUEY',
                              style: GoogleFonts.manrope(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // UUID block
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _kUuidBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              device.id.toString(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: _kMid,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Info row
          Row(
            children: [
              _InfoPill(
                icon: Icons.data_usage,
                label: 'MTU',
                value: '${connection.mtu}',
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Disconnect button
          GestureDetector(
            onTap: () async {
              await context.read<ConnectionCubit>().disconnect();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _kRedBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.link_off, size: 16, color: _kRed),
                  const SizedBox(width: 8),
                  Text(
                    'Disconnect',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _kRed,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Stress Tests button (visible only when peer hosts the stress service)
          if (_hasStressService(services))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StressTestsScreen(
                      connection: connection,
                    ),
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.bolt,
                        size: 16,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Stress Tests',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Info pill ───────────────────────────────────────────────────────────────

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _kUuidBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _kAccent),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: _kLight,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _kDark,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Service card ────────────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  final bluey.RemoteService service;
  final VoidCallback onTap;

  const _ServiceCard({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final serviceName = UuidNames.getServiceName(service.uuid);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: service.isPrimary ? _kIconBg : _kUuidBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.widgets_outlined,
                size: 18,
                color: service.isPrimary ? _kAccent : _kLight,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    serviceName ?? 'Unknown Service',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _kDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    service.uuid.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: _kLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${service.characteristics.length} characteristics',
                    style: GoogleFonts.inter(fontSize: 11, color: _kMid),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _kLight, size: 20),
          ],
        ),
      ),
    );
  }
}

bool _hasStressService(List<bluey.RemoteService>? services) {
  if (services == null) return false;
  return services.any(
    (s) =>
        s.uuid.toString().toLowerCase() ==
        StressProtocol.serviceUuid.toLowerCase(),
  );
}
