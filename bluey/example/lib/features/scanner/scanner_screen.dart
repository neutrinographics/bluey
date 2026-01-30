import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bluey/bluey.dart';

import '../../main.dart';
import '../../widgets/bluetooth_state_chip.dart';
import '../connection/connection_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final List<Device> _devices = [];
  StreamSubscription<Device>? _scanSubscription;
  BluetoothState _bluetoothState = BluetoothState.unknown;
  StreamSubscription<BluetoothState>? _stateSubscription;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initBluetooth();
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _stateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initBluetooth() async {
    final bluey = BlueyProvider.of(context);

    // Get initial state
    setState(() {
      _bluetoothState = bluey.currentState;
    });

    // Listen to state changes
    _stateSubscription = bluey.stateStream.listen((state) {
      setState(() {
        _bluetoothState = state;
      });
    });
  }

  Future<void> _startScan() async {
    final bluey = BlueyProvider.of(context);

    // Check if Bluetooth is ready
    if (!_bluetoothState.isReady) {
      _showError('Bluetooth is not ready. Current state: $_bluetoothState');
      return;
    }

    setState(() {
      _devices.clear();
      _isScanning = true;
    });

    try {
      final scanStream = bluey.scan(timeout: const Duration(seconds: 15));

      _scanSubscription = scanStream.listen(
        (device) {
          setState(() {
            // Update existing device or add new one
            final index = _devices.indexWhere((d) => d.id == device.id);
            if (index >= 0) {
              _devices[index] = device;
            } else {
              _devices.add(device);
            }
            // Sort by RSSI (strongest first)
            _devices.sort((a, b) => b.rssi.compareTo(a.rssi));
          });
        },
        onDone: () {
          setState(() {
            _isScanning = false;
          });
        },
        onError: (error) {
          setState(() {
            _isScanning = false;
          });
          _showError('Scan error: $error');
        },
      );
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      _showError('Failed to start scan: $e');
    }
  }

  Future<void> _stopScan() async {
    final bluey = BlueyProvider.of(context);
    await bluey.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _connectToDevice(Device device) async {
    // Stop scanning before connecting
    await _stopScan();

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ConnectionScreen(device: device)),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner'),
        actions: [
          BluetoothStateChip(state: _bluetoothState),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Scanning indicator
          if (_isScanning) const LinearProgressIndicator(),

          // Device list
          Expanded(
            child:
                _devices.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        return _DeviceCard(
                          device: device,
                          onTap: () => _connectToDevice(device),
                        );
                      },
                    ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScanning ? _stopScan : _startScan,
        icon: Icon(_isScanning ? Icons.stop : Icons.search),
        label: Text(_isScanning ? 'Stop' : 'Scan'),
        backgroundColor:
            _isScanning
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
        foregroundColor:
            _isScanning
                ? Theme.of(context).colorScheme.onError
                : Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }

  Widget _buildEmptyState() {
    // Show permission request UI if unauthorized
    if (_bluetoothState == BluetoothState.unauthorized) {
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
                onPressed: () async {
                  final bluey = BlueyProvider.of(context);
                  final granted = await bluey.authorize();
                  if (!granted && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Permission denied. Please grant permission in Settings.',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.lock_open),
                label: const Text('Grant Permission'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  final bluey = BlueyProvider.of(context);
                  await bluey.openSettings();
                },
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }

    // Show Bluetooth off UI
    if (_bluetoothState == BluetoothState.off) {
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
                onPressed: () async {
                  final bluey = BlueyProvider.of(context);
                  await bluey.requestEnable();
                },
                icon: const Icon(Icons.bluetooth),
                label: const Text('Enable Bluetooth'),
              ),
            ],
          ),
        ),
      );
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
            _isScanning
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

class _DeviceCard extends StatelessWidget {
  final Device device;
  final VoidCallback onTap;

  const _DeviceCard({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rssiColor = _getRssiColor(device.rssi);

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
          device.name ?? 'Unknown Device',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.id.toString(),
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
                  '${device.rssi} dBm',
                  style: theme.textTheme.bodySmall?.copyWith(color: rssiColor),
                ),
                if (device.advertisement.serviceUuids.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Icon(
                    Icons.widgets_outlined,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${device.advertisement.serviceUuids.length} services',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: theme.colorScheme.outline),
        onTap: onTap,
        isThreeLine: true,
      ),
    );
  }

  Color _getRssiColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }
}
