import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../../../shared/di/service_locator.dart';
import '../../../shared/presentation/bluetooth_state_chip.dart';
import '../../../shared/presentation/error_snackbar.dart';
import '../domain/use_cases/check_server_support.dart';
import '../domain/use_cases/start_advertising.dart';
import '../domain/use_cases/stop_advertising.dart';
import '../domain/use_cases/add_service.dart';
import '../domain/use_cases/send_notification.dart';
import '../domain/use_cases/observe_connections.dart';
import '../domain/use_cases/disconnect_central.dart';
import '../domain/use_cases/dispose_server.dart';
import 'server_cubit.dart';
import 'server_state.dart';

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
            disconnectCentral: getIt<DisconnectCentral>(),
            disposeServer: getIt<DisposeServer>(),
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
        final theme = Theme.of(context);

        if (!state.isSupported) {
          return Scaffold(
            appBar: AppBar(title: const Text('Server')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Server not supported',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This platform does not support the server role',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Server'),
            actions: [
              AdvertisingStateChip(isAdvertising: state.isAdvertising),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              _ServiceInfoCard(state: state),
              _ConnectedCentralsSection(state: state),
              const Divider(),
              _LogSection(log: state.log),
            ],
          ),
        );
      },
    );
  }
}

class _ServiceInfoCard extends StatelessWidget {
  final ServerScreenState state;

  const _ServiceInfoCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<ServerCubit>();

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
                  child: Icon(
                    Icons.cell_tower,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bluey Demo Service',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        ServerCubit.demoServiceUuid.toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed:
                      state.isAdvertising
                          ? cubit.stopAdvertising
                          : cubit.startAdvertising,
                  icon: Icon(
                    state.isAdvertising ? Icons.stop : Icons.play_arrow,
                  ),
                  label: Text(
                    state.isAdvertising
                        ? 'Stop Advertising'
                        : 'Start Advertising',
                  ),
                  style:
                      state.isAdvertising
                          ? FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                          )
                          : null,
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      state.connectedCentrals.isNotEmpty
                          ? cubit.sendNotification
                          : null,
                  icon: const Icon(Icons.send),
                  label: const Text('Send Notification'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedCentralsSection extends StatelessWidget {
  final ServerScreenState state;

  const _ConnectedCentralsSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('Connected Centrals', style: theme.textTheme.titleMedium),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 12,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  '${state.connectedCentrals.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (state.connectedCentrals.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No centrals connected',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: state.connectedCentrals.length,
              itemBuilder: (context, index) {
                final central = state.connectedCentrals[index];
                return _CentralChip(central: central);
              },
            ),
          ),
      ],
    );
  }
}

class _CentralChip extends StatelessWidget {
  final Central central;

  const _CentralChip({required this.central});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<ServerCubit>();

    return Card(
      margin: const EdgeInsets.only(right: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.phone_android,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  central.id.toString().substring(0, 8),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                Text('MTU: ${central.mtu}', style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => cubit.disconnectCentral(central),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Disconnect',
            ),
          ],
        ),
      ),
    );
  }
}

class _LogSection extends StatelessWidget {
  final List<ServerLogEntry> log;

  const _LogSection({required this.log});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<ServerCubit>();

    return Expanded(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Log', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: cubit.clearLog,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          Expanded(
            child:
                log.isEmpty
                    ? Center(
                      child: Text(
                        'No log entries',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: log.length,
                      itemBuilder: (context, index) {
                        final entry = log[index];
                        return _LogTile(entry: entry);
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final ServerLogEntry entry;

  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final color = switch (entry.tag) {
      'Advertising' => Colors.blue,
      'Connection' => Colors.green,
      'Notify' => Colors.purple,
      'Error' => Colors.red,
      _ => theme.colorScheme.outline,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatTime(entry.timestamp),
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              entry.tag,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(entry.message, style: theme.textTheme.bodySmall),
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
}
