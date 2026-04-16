import 'dart:ui';

import 'package:bluey/bluey.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/di/service_locator.dart';
import '../../../shared/presentation/error_snackbar.dart';
import '../application/connect_saved_peer.dart';
import '../application/discover_peers.dart';
import '../application/forget_saved_peer.dart';
import '../infrastructure/peer_storage.dart';
import 'peer_cubit.dart';
import 'peer_state.dart';

// -- Design tokens (matching scanner/connection screens) --

const _kBg = Color(0xFFF7F9FB);
const _kCard = Colors.white;
const _kAccent = Color(0xFF3F6187);
const _kDark = Color(0xFF2C3437);
const _kMid = Color(0xFF596064);
const _kLight = Color(0xFF747C80);
const _kHeaderText = Color(0xFF0F172A);
const _kGreen = Color(0xFF006D4A);
const _kGreenBg = Color(0x1A006D4A);
const _kRed = Color(0xFFA83836);
const _kRedBg = Color(0x1AA83836);
const _kIconBg = Color(0xFFAFD2FD);
const _kUuidBg = Color(0xFFF0F4F7);

// -- Screen --

class PeerScreen extends StatelessWidget {
  const PeerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => PeerCubit(
        discoverPeers: getIt<DiscoverPeers>(),
        connectSavedPeer: getIt<ConnectSavedPeer>(),
        forgetSavedPeer: getIt<ForgetSavedPeer>(),
        storage: getIt<PeerStorage>(),
      )..initialize(),
      child: const _PeerView(),
    );
  }
}

class _PeerView extends StatelessWidget {
  const _PeerView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PeerCubit, PeerState>(
      listenWhen: (previous, current) =>
          previous.error != current.error && current.error != null,
      listener: (context, state) {
        if (state.error != null) {
          ErrorSnackbar.show(context, state.error!);
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: _kBg,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const _TopBar(),
                Expanded(child: _buildContent(context, state)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, PeerState state) {
    return switch (state.status) {
      PeerScreenStatus.initial => _InitialState(),
      PeerScreenStatus.restoring => _RestoringState(
          savedPeerId: state.savedPeerId,
        ),
      PeerScreenStatus.discovering => const _DiscoveringState(),
      PeerScreenStatus.discovered => _DiscoveredState(peers: state.peers),
      PeerScreenStatus.connecting => const _ConnectingState(),
      PeerScreenStatus.connected => _ConnectedState(
          connection: state.connection!,
          savedPeerId: state.savedPeerId,
        ),
      PeerScreenStatus.error => _ErrorState(
          error: state.error ?? 'Unknown error',
          hasSavedPeer: state.savedPeerId != null,
        ),
    };
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
              const Icon(Icons.people_outline, color: _kHeaderText, size: 20),
              const SizedBox(width: 12),
              Text(
                'Peers',
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _kHeaderText,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              BlocBuilder<PeerCubit, PeerState>(
                builder: (context, state) {
                  if (state.savedPeerId == null) {
                    return const SizedBox.shrink();
                  }
                  return IconButton(
                    icon: const Icon(
                      Icons.link_off,
                      color: _kHeaderText,
                      size: 22,
                    ),
                    tooltip: 'Forget saved peer',
                    onPressed: () => _confirmForget(context),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmForget(BuildContext context) {
    final cubit = context.read<PeerCubit>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Forget Peer',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Clear the saved peer? You will need to rediscover it next time.',
          style: GoogleFonts.inter(color: _kMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: GoogleFonts.inter(color: _kMid)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              cubit.forgetPeer();
            },
            child: Text(
              'Forget',
              style: GoogleFonts.inter(
                color: _kRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Initial state --

class _InitialState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding:
          const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 120),
      children: [
        _HeroCard(
          title: 'Ready',
          subtitle:
              'Tap the button below to discover nearby Bluey servers.',
        ),
        const SizedBox(height: 24),
        _ActionButton(
          icon: Icons.search,
          label: 'Discover Bluey Peers',
          onTap: () => context.read<PeerCubit>().discover(),
        ),
      ],
    );
  }
}

// -- Restoring state --

class _RestoringState extends StatelessWidget {
  final ServerId? savedPeerId;

  const _RestoringState({this.savedPeerId});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding:
          const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 120),
      children: [
        _HeroCard(
          title: 'Reconnecting...',
          subtitle: 'Trying to reconnect to the saved peer.',
          isLoading: true,
        ),
        if (savedPeerId != null) ...[
          const SizedBox(height: 16),
          _UuidBlock(label: 'Saved Peer', value: savedPeerId!.value),
        ],
      ],
    );
  }
}

// -- Discovering state --

class _DiscoveringState extends StatelessWidget {
  const _DiscoveringState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding:
          const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 120),
      children: [
        _HeroCard(
          title: 'Scanning...',
          subtitle:
              'Searching for nearby Bluey servers. This may take a few seconds.',
          isLoading: true,
        ),
      ],
    );
  }
}

// -- Discovered state --

class _DiscoveredState extends StatelessWidget {
  final List<BlueyPeer> peers;

  const _DiscoveredState({required this.peers});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding:
          const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 120),
      children: [
        _HeroCard(
          title: '${peers.length} Found',
          subtitle:
              '${peers.length} Bluey server${peers.length == 1 ? '' : 's'} discovered nearby.',
        ),
        const SizedBox(height: 16),
        _ActionButton(
          icon: Icons.refresh,
          label: 'Rescan',
          onTap: () => context.read<PeerCubit>().discover(),
          compact: true,
        ),
        const SizedBox(height: 24),
        if (peers.isEmpty)
          _EmptyHint()
        else
          ...peers.map(
            (peer) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _PeerCard(peer: peer),
            ),
          ),
      ],
    );
  }
}

// -- Connecting state --

class _ConnectingState extends StatelessWidget {
  const _ConnectingState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding:
          const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 120),
      children: [
        _HeroCard(
          title: 'Connecting...',
          subtitle: 'Establishing connection to the selected peer.',
          isLoading: true,
        ),
      ],
    );
  }
}

// -- Connected state --

class _ConnectedState extends StatelessWidget {
  final Connection connection;
  final ServerId? savedPeerId;

  const _ConnectedState({
    required this.connection,
    this.savedPeerId,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding:
          const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 120),
      children: [
        _HeroCard(
          title: 'Connected',
          subtitle: 'You are connected to the Bluey peer.',
        ),
        const SizedBox(height: 24),
        // Connection info card
        Container(
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
                          'Bluey Peer',
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _kDark,
                          ),
                        ),
                        const SizedBox(height: 2),
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
                      ],
                    ),
                  ),
                ],
              ),
              if (savedPeerId != null) ...[
                const SizedBox(height: 20),
                _UuidBlock(label: 'Server ID', value: savedPeerId!.value),
              ],
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
                onTap: () => context.read<PeerCubit>().disconnect(),
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
            ],
          ),
        ),
      ],
    );
  }
}

// -- Error state --

class _ErrorState extends StatelessWidget {
  final String error;
  final bool hasSavedPeer;

  const _ErrorState({required this.error, required this.hasSavedPeer});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding:
          const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 120),
      children: [
        _HeroCard(
          title: 'Error',
          subtitle: error,
          dotColor: _kRed,
        ),
        const SizedBox(height: 24),
        _ActionButton(
          icon: Icons.refresh,
          label: 'Retry Discovery',
          onTap: () => context.read<PeerCubit>().discover(),
        ),
        if (hasSavedPeer) ...[
          const SizedBox(height: 12),
          _ActionButton(
            icon: Icons.link_off,
            label: 'Forget Saved Peer',
            onTap: () => context.read<PeerCubit>().forgetPeer(),
            color: _kRed,
          ),
        ],
      ],
    );
  }
}

// -- Reusable widgets --

class _HeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color? dotColor;
  final bool isLoading;

  const _HeroCard({
    required this.title,
    required this.subtitle,
    this.dotColor,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 160),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kCard,
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
                    color: _kDark,
                    letterSpacing: -1.5,
                    height: 1.2,
                  ),
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kAccent,
                  ),
                )
              else
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor ?? _kGreen,
                  ),
                ),
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
                color: _kMid,
                height: 1.625,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool compact;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = color ?? _kAccent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: compact ? 12 : 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: const Alignment(-0.7, -0.5),
            end: const Alignment(0.7, 0.5),
            colors: [bgColor, bgColor.withValues(alpha: 0.85)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: bgColor.withValues(alpha: 0.2),
              blurRadius: 15,
              offset: const Offset(0, 10),
              spreadRadius: -3,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerCard extends StatelessWidget {
  final BlueyPeer peer;

  const _PeerCard({required this.peer});

  @override
  Widget build(BuildContext context) {
    final id = peer.serverId.value;
    final shortId = '${id.substring(0, 8)}...${id.substring(id.length - 4)}';

    return GestureDetector(
      onTap: () => context.read<PeerCubit>().connectToPeer(peer),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _kIconBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.devices,
                size: 22,
                color: _kDark.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bluey Server',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _kDark,
                      height: 1.56,
                    ),
                  ),
                  Text(
                    shortId,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: _kLight,
                      letterSpacing: 0.55,
                      height: 1.5,
                    ),
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

class _UuidBlock extends StatelessWidget {
  final String label;
  final String value;

  const _UuidBlock({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kUuidBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _kLight,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: _kMid,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

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

class _EmptyHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 48),
          Icon(
            Icons.search_off,
            size: 48,
            color: const Color(0xFF94A3B8),
          ),
          const SizedBox(height: 16),
          Text(
            'No peers found',
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _kMid,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure a Bluey server is advertising nearby',
            style: GoogleFonts.inter(fontSize: 14, color: _kLight),
          ),
        ],
      ),
    );
  }
}
