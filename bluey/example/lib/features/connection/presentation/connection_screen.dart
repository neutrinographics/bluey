import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart' as bluey;

import '../../../shared/di/service_locator.dart';
import '../../../shared/presentation/bluetooth_state_chip.dart';
import '../../../shared/presentation/error_snackbar.dart';
import '../../../shared/domain/uuid_names.dart';
import '../../service_explorer/presentation/service_screen.dart';
import '../application/connect_to_device.dart';
import '../application/disconnect_device.dart';
import '../application/get_services.dart';
import 'connection_cubit.dart';
import 'connection_state.dart';

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
        // Listen for disconnection events
        if (previous.connectionState != bluey.ConnectionState.disconnected &&
            current.connectionState == bluey.ConnectionState.disconnected &&
            current.error != null) {
          return true;
        }
        // Listen for errors
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
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(
            title: Text(state.device.name ?? 'Unknown Device'),
            actions: [
              ConnectionStateChip(state: state.connectionState),
              const SizedBox(width: 8),
            ],
          ),
          body: _buildBody(context, state, theme),
          floatingActionButton:
              state.connectionState.isConnected
                  ? FloatingActionButton.extended(
                    onPressed: () async {
                      await context.read<ConnectionCubit>().disconnect();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect'),
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  )
                  : null,
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    ConnectionScreenState state,
    ThemeData theme,
  ) {
    if (state.connectionState == bluey.ConnectionState.connecting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connecting...'),
          ],
        ),
      );
    }

    if (state.error != null && !state.connectionState.isConnected) {
      return _ErrorState(error: state.error!);
    }

    if (!state.connectionState.isConnected) {
      return const Center(child: Text('Not connected'));
    }

    return Column(
      children: [
        _DeviceInfoCard(device: state.device, connection: state.connection!),
        _ServicesHeader(
          servicesCount: state.services?.length,
          isDiscovering: state.isDiscovering,
        ),
        Expanded(
          child:
              state.services == null || state.services!.isEmpty
                  ? Center(
                    child: Text(
                      state.isDiscovering
                          ? 'Discovering services...'
                          : 'No services found',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                  : _ServicesList(
                    services: state.services!,
                    connection: state.connection!,
                  ),
        ),
      ],
    );
  }

  void _showDisconnectedDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Disconnected'),
            content: const Text('The device has been disconnected.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('OK'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  context.read<ConnectionCubit>().connect();
                },
                child: const Text('Reconnect'),
              ),
            ],
          ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;

  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<ConnectionCubit>();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Connection Failed', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: cubit.connect,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceInfoCard extends StatelessWidget {
  final bluey.Device device;
  final bluey.Connection connection;

  const _DeviceInfoCard({required this.device, required this.connection});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  radius: 24,
                  child: Icon(
                    Icons.bluetooth_connected,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name ?? 'Unknown Device',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        device.id.toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _InfoItem(
                  icon: Icons.signal_cellular_alt,
                  label: 'RSSI',
                  value: '${device.rssi} dBm',
                ),
                _InfoItem(
                  icon: Icons.data_usage,
                  label: 'MTU',
                  value: '${connection.mtu}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.labelSmall),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _ServicesHeader extends StatelessWidget {
  final int? servicesCount;
  final bool isDiscovering;

  const _ServicesHeader({
    required this.servicesCount,
    required this.isDiscovering,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<ConnectionCubit>();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text('Services', style: theme.textTheme.titleMedium),
          const SizedBox(width: 8),
          if (isDiscovering)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (servicesCount != null)
            Text(
              '($servicesCount)',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          const Spacer(),
          if (!isDiscovering)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: cubit.loadServices,
              tooltip: 'Refresh services',
            ),
        ],
      ),
    );
  }
}

class _ServicesList extends StatelessWidget {
  final List<bluey.RemoteService> services;
  final bluey.Connection connection;

  const _ServicesList({required this.services, required this.connection});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final service = services[index];
        return _ServiceCard(
          service: service,
          onTap: () => _openService(context, service),
        );
      },
    );
  }

  void _openService(BuildContext context, bluey.RemoteService service) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) =>
                ServiceScreen(connection: connection, service: service),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final bluey.RemoteService service;
  final VoidCallback onTap;

  const _ServiceCard({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serviceName = UuidNames.getServiceName(service.uuid);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              service.isPrimary
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.secondaryContainer,
          child: Icon(
            Icons.widgets,
            color:
                service.isPrimary
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(
          serviceName ?? 'Unknown Service',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              service.uuid.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            Text(
              '${service.characteristics.length} characteristics',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: theme.colorScheme.outline),
        onTap: onTap,
        isThreeLine: true,
      ),
    );
  }
}
