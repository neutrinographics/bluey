import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../../../shared/di/service_locator.dart';
import '../../../shared/presentation/bluetooth_state_chip.dart';
import '../../../shared/presentation/error_snackbar.dart';
import '../../connection/presentation/connection_screen.dart';
import '../application/scan_for_devices.dart';
import '../application/stop_scan.dart';
import '../application/get_bluetooth_state.dart';
import '../application/request_permissions.dart';
import '../application/request_enable.dart';
import 'scanner_cubit.dart';
import 'scanner_state.dart';

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
          appBar: AppBar(
            title: const Text('Scanner'),
            actions: [
              BluetoothStateChip(state: state.bluetoothState),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              if (state.isScanning) const LinearProgressIndicator(),
              Expanded(
                child:
                    state.scanResults.isEmpty
                        ? _EmptyState(
                          bluetoothState: state.bluetoothState,
                          isScanning: state.isScanning,
                        )
                        : _ScanResultList(scanResults: state.scanResults),
              ),
            ],
          ),
          floatingActionButton: _ScanButton(isScanning: state.isScanning),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final BluetoothState bluetoothState;
  final bool isScanning;

  const _EmptyState({required this.bluetoothState, required this.isScanning});

  @override
  Widget build(BuildContext context) {
    if (bluetoothState == BluetoothState.unauthorized) {
      return _UnauthorizedState();
    }

    if (bluetoothState == BluetoothState.off) {
      return _BluetoothOffState();
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bluetooth_searching,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            isScanning
                ? 'Scanning for devices...'
                : 'Tap Scan to find nearby devices',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnauthorizedState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ScannerCubit>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Bluetooth Permission Required',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This app needs Bluetooth permission to scan for and connect to BLE devices.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => cubit.requestPermissions(),
              icon: const Icon(Icons.lock_open),
              label: const Text('Grant Permission'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => cubit.openSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BluetoothOffState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ScannerCubit>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_disabled,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Bluetooth is Off',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Please enable Bluetooth to scan for devices.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => cubit.requestEnable(),
              icon: const Icon(Icons.bluetooth),
              label: const Text('Enable Bluetooth'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanResultList extends StatelessWidget {
  final List<ScanResult> scanResults;

  const _ScanResultList({required this.scanResults});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: scanResults.length,
      itemBuilder: (context, index) {
        final result = scanResults[index];
        return _ScanResultCard(result: result);
      },
    );
  }
}

class _ScanResultCard extends StatelessWidget {
  final ScanResult result;

  const _ScanResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rssiColor = _getRssiColor(result.rssi);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.bluetooth,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          result.device.name ?? 'Unknown Device',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.device.id.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.signal_cellular_alt, size: 16, color: rssiColor),
                const SizedBox(width: 4),
                Text(
                  '${result.rssi} dBm',
                  style: theme.textTheme.bodySmall?.copyWith(color: rssiColor),
                ),
                if (result.advertisement.serviceUuids.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Icon(
                    Icons.widgets_outlined,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${result.advertisement.serviceUuids.length} services',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: theme.colorScheme.outline),
        onTap: () => _connectToDevice(context, result.device),
        isThreeLine: true,
      ),
    );
  }

  Color _getRssiColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }

  Future<void> _connectToDevice(BuildContext context, Device device) async {
    // Stop scanning before connecting
    await context.read<ScannerCubit>().stopScan();

    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ConnectionScreen(device: device)),
    );
  }
}

class _ScanButton extends StatelessWidget {
  final bool isScanning;

  const _ScanButton({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ScannerCubit>();
    final theme = Theme.of(context);

    return FloatingActionButton.extended(
      onPressed: isScanning ? cubit.stopScan : cubit.startScan,
      icon: Icon(isScanning ? Icons.stop : Icons.search),
      label: Text(isScanning ? 'Stop' : 'Scan'),
      backgroundColor:
          isScanning ? theme.colorScheme.error : theme.colorScheme.primary,
      foregroundColor:
          isScanning ? theme.colorScheme.onError : theme.colorScheme.onPrimary,
    );
  }
}
