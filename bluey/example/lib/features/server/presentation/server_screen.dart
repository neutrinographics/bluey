import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/di/service_locator.dart';
import '../../../shared/presentation/error_snackbar.dart';
import '../application/check_server_support.dart';
import '../application/start_advertising.dart';
import '../application/stop_advertising.dart';
import '../application/add_service.dart';
import '../application/send_notification.dart';
import '../application/observe_connections.dart';
import '../application/disconnect_client.dart';
import '../application/dispose_server.dart';
import '../application/get_connected_clients.dart';
import '../application/observe_disconnections.dart';
import '../application/handle_requests.dart';
import 'server_cubit.dart';
import 'server_state.dart';

// -- Design tokens --

const _kBackgroundColor = Color(0xFFF7F9FB);
const _kTextDark = Color(0xFF2C3437);
const _kTextMedium = Color(0xFF596064);
const _kHeaderText = Color(0xFF0F172A);
const _kAccentBlue = Color(0xFF3F6187);
const _kGreen = Color(0xFF006D4A);
const _kGreenDark = Color(0xFF005A3C);
const _kGreenBg = Color(0x1A006D4A); // 10% green
const _kClientIconBg = Color(0xFFD3E4FE);
const _kPillBg = Color(0xFFE3E9ED);
const _kLogBg = Color(0xFFF0F4F7);
const _kLogBorder = Color(0xFFDCE4E8);

// -- Log tag colors --

Color _tagBgColor(String tag) => switch (tag) {
  'Write' => const Color(0xFFAFD2FD),
  'Connection' => const Color(0x1A006D4A),
  'Read' => const Color(0xFFD3E4FE),
  _ => const Color(0x0D2C3437),
};

Color _tagTextColor(String tag) => switch (tag) {
  'Write' => const Color(0xFF23486C),
  'Connection' => _kGreenDark,
  'Read' => _kTextDark,
  _ => _kTextDark,
};

// -- Server Screen --

class ServerScreen extends StatelessWidget {
  const ServerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (context) => ServerCubit(
            checkServerSupport: getIt<CheckServerSupport>(),
            startAdvertising: getIt<StartAdvertising>(),
            stopAdvertising: getIt<StopAdvertising>(),
            addService: getIt<AddService>(),
            sendNotification: getIt<SendNotification>(),
            observeConnections: getIt<ObserveConnections>(),
            disconnectClient: getIt<DisconnectClient>(),
            disposeServer: getIt<DisposeServer>(),
            getConnectedClients: getIt<GetConnectedClients>(),
            observeDisconnections: getIt<ObserveDisconnections>(),
            observeReadRequests: getIt<ObserveReadRequests>(),
            observeWriteRequests: getIt<ObserveWriteRequests>(),
          )..initialize(),
      child: const ScaffoldMessenger(child: _ServerView()),
    );
  }
}

class _ServerView extends StatelessWidget {
  const _ServerView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ServerCubit, ServerScreenState>(
      listenWhen:
          (previous, current) =>
              previous.error != current.error && current.error != null,
      listener: (context, state) {
        if (state.error != null) {
          ErrorSnackbar.show(context, state.error!);
          context.read<ServerCubit>().clearError();
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
                Expanded(
                  child:
                      state.isSupported
                          ? _ServerContent(state: state)
                          : const _UnsupportedState(),
                ),
              ],
            ),
          ),
        );
      },
    );
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
            ],
          ),
        ),
      ),
    );
  }
}

// -- Main server content --

class _ServerContent extends StatelessWidget {
  final ServerScreenState state;

  const _ServerContent({required this.state});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 128),
      children: [
        _HeroCard(state: state),
        const SizedBox(height: 24),
        _ActiveClientsCard(count: state.connectedClients.length),
        const SizedBox(height: 40),
        if (state.connectedClients.isNotEmpty) ...[
          _ConnectedClientsSection(clients: state.connectedClients),
          const SizedBox(height: 40),
        ],
        _LogSection(log: state.log),
      ],
    );
  }
}

// -- Hero card --

class _HeroCard extends StatelessWidget {
  final ServerScreenState state;

  const _HeroCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ServerCubit>();

    return Container(
      constraints: const BoxConstraints(minHeight: 240),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status indicator
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.isAdvertising ? _kAccentBlue : _kPillBg,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                state.isAdvertising ? 'ADVERTISING' : 'IDLE',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: state.isAdvertising ? _kAccentBlue : _kTextMedium,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Device name
          Text(
            ServerCubit.advertisedName,
            style: GoogleFonts.manrope(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: _kTextDark,
              height: 1.11,
            ),
          ),
          const SizedBox(height: 8),
          // Service UUID
          Row(
            children: [
              Icon(Icons.signal_wifi_4_bar, size: 13, color: _kTextMedium),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ServerCubit.demoServiceUuid.toString(),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: _kTextMedium,
                    height: 1.43,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Action buttons
          _ActionButton(
            label:
                state.isAdvertising ? 'Stop Advertising' : 'Start Advertising',
            icon:
                state.isAdvertising
                    ? Icons.stop_circle_outlined
                    : Icons.play_arrow,
            isPrimary: true,
            onPressed:
                state.isAdvertising
                    ? cubit.stopAdvertising
                    : cubit.startAdvertising,
          ),
          const SizedBox(height: 16),
          _ActionButton(
            label: 'Send Notification',
            icon: Icons.notifications_active_outlined,
            isPrimary: false,
            onPressed:
                state.connectedClients.isNotEmpty
                    ? cubit.sendNotification
                    : null,
          ),
        ],
      ),
    );
  }
}

// -- Action button --

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment(-0.7, -0.5),
              end: Alignment(0.7, 0.5),
              colors: [Color(0xFF3F6187), Color(0xFF32557A)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _kAccentBlue.withValues(alpha: 0.2),
                blurRadius: 15,
                offset: const Offset(0, 10),
                spreadRadius: -3,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          color: onPressed != null ? _kPillBg : _kPillBg.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color:
                  onPressed != null
                      ? _kTextDark
                      : _kTextDark.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color:
                    onPressed != null
                        ? _kTextDark
                        : _kTextDark.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Active clients counter card --

class _ActiveClientsCard extends StatelessWidget {
  final int count;

  const _ActiveClientsCard({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(33),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _kGreenBg,
            ),
            child: const Icon(Icons.cell_tower, size: 30, color: _kGreen),
          ),
          const SizedBox(height: 16),
          Text(
            count.toString().padLeft(2, '0'),
            style: GoogleFonts.manrope(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: _kGreen,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ACTIVE CLIENTS',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _kGreenDark,
              letterSpacing: -0.6,
            ),
          ),
        ],
      ),
    );
  }
}

// -- Connected clients section --

class _ConnectedClientsSection extends StatelessWidget {
  final List<Client> clients;

  const _ConnectedClientsSection({required this.clients});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Connected Clients',
            style: GoogleFonts.manrope(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _kTextDark,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 24),
        ...clients.map(
          (client) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _ClientCard(client: client),
          ),
        ),
      ],
    );
  }
}

// -- Client card --

class _ClientCard extends StatelessWidget {
  final Client client;

  const _ClientCard({required this.client});

  @override
  Widget build(BuildContext context) {
    final isHighMtu = client.mtu > 100;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _kClientIconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.smartphone,
                  size: 20,
                  color: _kTextDark.withValues(alpha: 0.7),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isHighMtu ? Colors.transparent : _kPillBg,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  'MTU ${client.mtu}',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isHighMtu ? _kGreenDark : _kTextMedium,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            client.id.toShortString(),
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _kTextDark,
              height: 1.5,
            ),
          ),
          Text(
            client.id.toString(),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: _kTextMedium,
              height: 1.33,
            ),
          ),
        ],
      ),
    );
  }
}

// -- Log section --

class _LogSection extends StatelessWidget {
  final List<ServerLogEntry> log;

  const _LogSection({required this.log});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ServerCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Event Log',
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _kTextDark,
                  height: 1.4,
                ),
              ),
              if (log.isNotEmpty)
                GestureDetector(
                  onTap: cubit.clearLog,
                  child: Text(
                    'Clear all',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _kAccentBlue,
                      height: 1.43,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (log.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: _kLogBg,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(
              child: Text(
                'No events yet',
                style: GoogleFonts.inter(fontSize: 14, color: _kTextMedium),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: _kLogBg,
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < log.length; i++) ...[
                  _LogEntry(entry: log[i], showTopBorder: i > 0),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// -- Log entry --

class _LogEntry extends StatelessWidget {
  final ServerLogEntry entry;
  final bool showTopBorder;

  const _LogEntry({required this.entry, required this.showTopBorder});

  @override
  Widget build(BuildContext context) {
    final bgColor = _tagBgColor(entry.tag);
    final textColor = _tagTextColor(entry.tag);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: showTopBorder ? null : Colors.white,
        border:
            showTopBorder
                ? const Border(top: BorderSide(color: _kLogBorder))
                : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _formatTime(entry.timestamp),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: _kTextMedium,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        entry.tag.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _extractTitle(entry.message),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _kTextDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  entry.message,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: _kTextMedium,
                    height: 1.43,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  String _extractTitle(String message) {
    final parts = message.split(':');
    if (parts.length > 1) return parts.first.trim();
    final words = message.split(' ');
    return words.take(3).join(' ');
  }
}

// -- Unsupported state --

class _UnsupportedState extends StatelessWidget {
  const _UnsupportedState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 120),
      children: [
        Container(
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
                      'Not\nSupported',
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
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'This platform does not support the BLE server role.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: _kTextMedium,
                  height: 1.625,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
